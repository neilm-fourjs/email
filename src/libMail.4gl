#+
#+ A library for interfacing with IMAPI/SMTP mail servers - only tested 
#+ so far with googlemail. -- loosly based on java mail api demos.
#+ Required Genero 2.21 or above
#+ Java and mail.jar(Java mail API)
#+
#+ This module initially written by: Neil J.Martin ( neilm@4js.com ) 
#+
#+ Code should be self-documenting: 
#+ -Comments should be avoided whenever possible. 
#+ -Comments duplicate work when both writing and reading code. 
#+ -If you need to comment something to make it understandable it should probably be rewritten.
#+
IMPORT os
IMPORT FGL libMailLog
-- Includes for the Java libraries used.
&include "libMailJava.inc"

&define D_ANSWERED "em_answered"
&define D_FORWARDED "em_forwarded"
&define D_FORW_ANSW "em_forw_answ"
&define D_ATTACH "em_attachment"
&define D_JUNK "em_junk-col"

CONSTANT VER = "UNK"
CONSTANT PRG = "libMail"
CONSTANT PRGDESC = "4gl/Java Mail Api"
CONSTANT PRGAUTH = "Neil J.Martin"

-- Flag for if processed. Becomes xxx00000yy where yy=head_key from insert.
CONSTANT MYFLAG = "fjs"
CONSTANT GUI = 0
CONSTANT STRINGLIMIT = 1000000

CONSTANT c_debug BOOLEAN = FALSE
CONSTANT saveAttachments BOOLEAN = TRUE

&ifdef DBG
CONSTANT clr_flags BOOLEAN = TRUE  -- development and testing only
#CONSTANT debugLevel = 4 -- 0=no output.
&else
CONSTANT clr_flags BOOLEAN = FALSE  -- development and testing only
#CONSTANT debugLevel = 0 -- 0=no output.
&endif

-- Types and Record Definitions.
&include "libMail.inc"

&define MAILDEBUG( lev, msg ) \
	CALL logDebug( __LINE__, __FILE__, lev, NVL(msg,"NULL!"))

-- Email Icons 
{ SEE cl_globs.inc
&define D_ANSWERED "em_answered"
&define D_FORWARDED "em_forwarded"
&define D_FORW_ANSW "em_forw_answ"
&define D_ATTACH "em_attachment"
&define D_JUNK "em_junk-col"
}

-- Folder Icons
&define D_FLD_DEF "em_folder-0"  
&define D_FLD_INBOX "em_folder-5"
&define D_FLD_SENT "em_folder-12"
&define D_FLD_JUNK "em_folder-6"
&define D_FLD_GMAIL "em_folder-14"
&define D_FLD_DELETED "em_folder-10"

#+ public Email Headers - populated by called mailFetch( "inbox" )
PUBLIC DEFINE mails DYNAMIC ARRAY OF t_mail
#+ List of receipents for mail - recps[ mail_no ].recp[ x ].*
PUBLIC DEFINE recps DYNAMIC ARRAY OF RECORD
		recp DYNAMIC ARRAY OF t_recp
	END RECORD
#+ Results from reading folder with mailFetch
PUBLIC DEFINE totalMessages, newMessages INTEGER

#+ Body of mail fetched with mailRetvBody( mail_no ) - plain text
PUBLIC DEFINE emailBody STRING
PUBLIC DEFINE sb_emailBody base.StringBuffer
PUBLIC DEFINE emailHTMLBody STRING
PUBLIC DEFINE sb_emailHTMLBody base.StringBuffer
#+ Flag to say if the body is HTML.
PUBLIC DEFINE emailBodyHTML BOOLEAN

#+ Array of colours set for use with DIALOG.setAttributes
PUBLIC DEFINE colr_mails DYNAMIC ARRAY OF t_colr_mail

#+ Array mail boxes found on server.
PUBLIC DEFINE mboxes DYNAMIC ARRAY OF t_mbox

#+ SMTP sending receipents.
PUBLIC DEFINE smtp_to DYNAMIC ARRAY OF STRING
PUBLIC DEFINE smtp_cc DYNAMIC ARRAY OF STRING
PUBLIC DEFINE smtp_bcc DYNAMIC ARRAY OF STRING
PUBLIC DEFINE smtp_replyTo STRING
PUBLIC DEFINE smtp_attachements DYNAMIC ARRAY OF STRING

#+ Use a Database
PUBLIC DEFINE use_db BOOLEAN
#+ Use database instead of connecting to mail server.
PUBLIC DEFINE online BOOLEAN

#+ Private module variables.
DEFINE m_user VARCHAR(50) -- Current Account name
DEFINE m_mbox VARCHAR(50) -- Current Folder name
DEFINE m_bodyPart, m_mime_type STRING
DEFINE m_partNo SMALLINT
DEFINE m_charset STRING
DEFINE m_level SMALLINT
DEFINE m_attnum INTEGER
DEFINE folderOpen BOOLEAN
DEFINE folderReadOnly BOOLEAN
DEFINE m_attpath STRING
DEFINE m_debugText STRING

DEFINE m_msgs ARRAY [] OF Message
DEFINE m_imap_session Session
DEFINE m_store Store
DEFINE m_folder Folder

-- SMTP
DEFINE smtp_session Session
DEFINE smtp_host STRING
DEFINE smtp_from STRING
DEFINE smtp_pass STRING
DEFINE smtp_debug BOOLEAN

--------------------------------------------------------------------------------
#+ Connect to mail server
#+
#+ @param l_protocol imaps
#+ @param l_port 993
#+ @param l_host imap.googlemail.com
#+ @param l_user me@gmail.com
#+ @param l_password iamagod
PUBLIC FUNCTION mailConnect(l_protocol, l_port, l_host, l_user, l_password)
	DEFINE l_protocol STRING
	DEFINE l_port INTEGER
	DEFINe l_user VARCHAR(50)
	DEFINE l_host, l_password STRING
	DEFINE l_props Properties
	DEFINE i SMALLINT
	DEFINE mbox t_mbox

	LET m_attpath = fgl_getEnv("MAILATCH")

-- Get a Properties object
	LET l_props = System.getProperties()

-- Get a Session object
	LET m_imap_session = javax.mail.Session.getInstance(l_props) --, auth)
	CALL m_imap_session.setDebug(c_debug)

-- Get a Store object
	LET m_store = m_imap_session.getStore(l_protocol)
	LET m_user = l_user
-- Connect
	MAILDEBUG(0,"Protocol:"||l_protocol||" Host:"||l_host||" Port:"||l_port||" User:"||l_user)
	TRY
		CALL m_store.connect(l_host, l_port, l_user, l_password)
	CATCH
		LET online = FALSE	
		MAILDEBUG(-1,"Connection failed!")
		RETURN FALSE
	END TRY
-- Open the default Folder
	LET m_folder = m_store.getDefaultFolder()
	IF m_folder IS NULL THEN
		MAILDEBUG(-1,"ERR:No default folder")
		EXIT PROGRAM 1
	END IF

	CALL mboxes.clear()
	CALL mailFolders(m_folder,0) -- Get Folder List
	LET folderOpen = FALSE
	IF use_db THEN -- replace folder list
		DELETE FROM imapi_folders WHERE account = l_user
		FOR i = 1 TO mboxes.getLength()
			LET mbox.* = mboxes[i].*
			INSERT INTO imapi_folders VALUES( l_user, 
																	mbox.name, 
																	mbox.fullname, 
																	mbox.img,
																	mbox.id,
																	mbox.pid,
																	0, 0 )
		END FOR
	END IF
	LET online = TRUE
	RETURN TRUE
END FUNCTION
--------------------------------------------------------------------------------
PUBLIC FUNCTION mailClose()
	TRY
		MAILDEBUG(3,"Close")
		CALL m_folder.close(false)
		CALL m_store.close()
	CATCH
	END TRY
END FUNCTION
--------------------------------------------------------------------------------
#+ Fetch Emails
#+
#+ @param mbox Mail Box folder eg INBOX
#+ @param limit Number of mails to process: 0 = all.
PUBLIC FUNCTION mailFetch(mbox, limit)
	DEFINE mbox STRING
	DEFINE limit SMALLINT
	DEFINE i SMALLINT
	DEFINE fp FetchProfile

	IF mbox IS NULL THEN LET mbox = "inbox" END IF

	LET m_mbox = mbox
	LET m_attnum = 1
	LET m_level = 0
	IF NOT online THEN
		CALL mailDBFetch(mbox)
		RETURN TRUE
	END IF

	IF m_folder IS NOT NULL THEN
		TRY
			IF m_folder.isOpen() THEN
				CALL m_folder.close(false)
			END IF
			LET folderOpen = FALSE
		CATCH
		END TRY
	END IF
	LET m_folder = m_store.getDefaultFolder()
	LET m_folder = m_folder.getFolder(mbox)
	IF m_folder IS NULL THEN
		MAILDEBUG(-1,"Invalid folder! "||mbox)
		RETURN FALSE
	END IF

	LET folderReadOnly = FALSE
	CALL mails.clear()
	CALL mailStatus(__LINE__,"Opening folder...")
-- try to open read/write and IF that fails try read-only
	TRY
		CALL m_folder.open( javax.mail.Folder.READ_WRITE )
		MAILDEBUG(3,"folder open as READ-WRITE")
	CATCH
		TRY
			CALL m_folder.open( javax.mail.Folder.READ_ONLY )
			MAILDEBUG(0,"folder open as READ-ONLY")
			LET folderReadOnly = TRUE
		CATCH
			MAILDEBUG(-1,"Failed to open folder! "||mbox)
			RETURN FALSE
		END TRY
	END TRY	
	LET folderOpen = TRUE

	LET totalMessages = m_folder.getMessageCount()
	IF totalMessages = 0 THEN
		CALL mailStatus(__LINE__,"Empty folder")
		RETURN FALSE
	END IF

	LET newMessages = m_folder.getNewMessageCount()
	MAILDEBUG(3,"Message "||totalMessages||"("||newMessages||")")
	-- Attributes & Flags for all messages ..
	LET m_msgs = m_folder.getMessages()

	-- Use a suitable FetchProfile
	LET fp = FetchProfile.create()
	CALL fp.add( javax.mail.FetchProfile.Item.ENVELOPE)
	CALL fp.add( javax.mail.FetchProfile.Item.FLAGS)
	CALL fp.add("X-Mailer")
	CALL m_folder.fetch(m_msgs, fp)

	CALL mailStatus(__LINE__,"Reading Headers, limit="||limit||" ...")
	FOR i = 1 TO m_msgs.getLength()
		MAILDEBUG(3,"--------------------------")
		MAILDEBUG(3,"MESSAGE #" || (i) || ":")
		CALL mailRetvEnvelope(i, m_msgs[i])
		IF i = limit THEN EXIT FOR END IF
	END FOR

	CALL mailStatus(__LINE__,"Mails "||totalMessages||"("||newMessages||")")
	RETURN TRUE

END FUNCTION
--------------------------------------------------------------------------------
PUBLIC FUNCTION mailRetvBody(msgnum)
	DEFINE msgnum INTEGER
	DEFINE m Message

	IF use_db THEN
		IF mailDBretv(msgnum) THEN RETURN TRUE END IF
	END IF

	LET m_level = 0
	LET emailBody = "" -- "(null)" --base.Stringbuffer.create()
	LET emailHTMLBody = ""
	IF sb_emailBody IS NULL THEN
		LET sb_emailBody = base.Stringbuffer.create()
	ELSE
		CALL sb_emailBody.clear()
	END IF
	IF sb_emailHTMLBody IS NULL THEN
		LET sb_emailHTMLBody = base.Stringbuffer.create()
	ELSE
		CALL sb_emailHTMLBody.clear()
	END IF
	MAILDEBUG(3,"Getting message number: " || msgnum)
	TRY
		LET m = m_folder.getMessage(msgnum)
		LET m_partNo = 0
		IF mailRetvPart(m, msgnum, 0, 0) THEN
			RETURN TRUE
		END IF
	CATCH
		MAILDEBUG(-1,"ERR:Message number out of range")
	END TRY
	RETURN FALSE

END FUNCTION
--------------------------------------------------------------------------------
PUBLIC FUNCTION mailSetFlag( mno, value )
	DEFINE mno INTEGER
	DEFINE value STRING
	DEFINE m Message
	DEFINE flags Flags

	LET m = m_msgs[mno]
	LET flags = m.getFlags()
-- Update my flag.
	IF NOT folderReadOnly THEN
		MAILDEBUG(3,"Updating flags: "||value)
		CALL flags.add( value )
		CALL m_folder.setFlags(mno, mno, flags, TRUE )
		-- CALL m.saveChanges() -- crashes: .IllegalWriteException: IMAPMessage is read-only
	END IF
END FUNCTION
--------------------------------------------------------------------------------
#+ Copy a list of mails to a folder
#+
#+ @param l_mail_no Array of Integers for message numbers.
PUBLIC FUNCTION mailDelete( l_mail_no )
	DEFINE l_mail_no INTEGER
	DEFINE m Message

	TRY
		LET m = m_msgs[ l_mail_no ]
		CALL m.setFlag( Flags.Flag.DELETED, TRUE )
		MAILDEBUG(3,"mailDelete: "||l_mail_no||" Okay")
	CATCH
		MAILDEBUG(-1,"ERR:mailDelete: "||l_mail_no||" Failed!")
	END TRY

END FUNCTION
--------------------------------------------------------------------------------
#+ Copy a list of mails to a folder
#+
#+ @param l_mail_nos Array of Integers for message numbers.
#+ @param l_folder Name of folder
#+ @return a 0 or -1 plus a message.
PUBLIC FUNCTION mailCopyMesgs( l_mail_nos, l_folder )
	TYPE m_arr ARRAY [] OF Message
	DEFINE l_mail_nos DYNAMIC ARRAY OF INTEGER
	DEFINE l_folder STRING
	DEFINE f Folder
	DEFINE l_msgs m_arr
	DEFINE x INTEGER

	TRY -- Get folder
		LET f = m_store.getFolder( l_folder )
	CATCH
		MAILDEBUG(-1,"ERR:mailCopyMesgs: Invalid Folder")
		RETURN -1, "Invalid Folder"
	END TRY

	LET l_msgs = m_arr.create( l_mail_nos.getLength() )
	FOR x = 1 TO l_mail_nos.getLength()
		LET l_msgs[x] = m_msgs[ l_mail_nos[x] ]
	END FOR

	TRY -- Do the copy.
		CALL m_folder.copyMessages(l_msgs, f)
	CATCH
		MAILDEBUG(-1,"ERR:mailCopyMesgs: Copy failed")
		RETURN -1, "Copy failed"
	END TRY
	MAILDEBUG(3,"mailCopyMesgs: Copy okay")
	RETURN 0, "Copied."
	
END FUNCTION

#+ SMTP Functions
--------------------------------------------------------------------------------
#+ must be called before you can call mailSmtpSend.
PUBLIC FUNCTION mailSmtpInit(l_host, l_from, l_pass, l_reply, l_debug )
	DEFINE l_host,  l_from, l_pass, l_reply, l_debug STRING
	DEFINE smtp_props Properties

	LET smtp_host = l_host
	LET smtp_from = l_from
	LET smtp_pass = l_pass
	LET smtp_debug = l_debug
	LET smtp_replyTo = l_reply

	IF l_debug IS NULL THEN LET libMailLog.m_debugLevel = 0 END IF

	LET libMailLog.m_debugLevel = l_debug

	IF l_host IS NULL THEN
		RETURN FALSE
	END IF

	MAILDEBUG(0,"mailSmtpInit-host:"||NVL(l_host,"NULL")||" from:"||NVL(l_from,"NULL")||" debug:"||NVL(l_debug,"NULL"))

-- create some properties and get the default Session
	TRY
		LET smtp_props = Properties.create()
		CALL smtp_props.put("mail.smtp.host", smtp_host);
		CALL smtp_props.put("mail.smtps.auth", "true");
		IF c_debug THEN
			CALL smtp_props.put("mail.debug", "true")
		ELSE
			CALL smtp_props.put("mail.debug", "false")
		END IF
	CATCH
		MAILDEBUG(0,"mailSmtpInit: Properties.create() FAILED!")
		RETURN FALSE
	END TRY

	TRY
		LET smtp_session = javax.mail.Session.getInstance(smtp_props);
	CATCH
		MAILDEBUG(0,"mailSmtpInit: javax.mail.Session.getInstance FAILED!")
		RETURN FALSE
	END TRY

	TRY
		CALL smtp_session.setDebug(c_debug);
	CATCH
		MAILDEBUG(0,"mailSmtpInit: smtp_session.setDebug(c_debug) FAILED!")
		RETURN FALSE
	END TRY

	LET m_charset = getCharSet()
	MAILDEBUG(0,"mailSmtpInit Okay")
	RETURN TRUE

END FUNCTION
--------------------------------------------------------------------------------
#+ Send mail via SMTP - must call mailSmptInit first.
PUBLIC FUNCTION mailSmtpSend(l_subj, l_msg, l_texttype)
	TYPE ia ARRAY [] OF javax.mail.internet.InternetAddress
	TYPE mbp ARRAY [] OF javax.mail.internet.MimeBodyPart
	DEFINE l_subj, l_msg, l_texttype, l_file STRING
	DEFINE msg MimeMessage
	DEFINE mbps mbp
	DEFINE mp MimeMultipart
	DEFINE to_add, cc_add, bcc_add, replyTo ia
	DEFINE invalid, validUnsent, validSent ARRAY [] OF Address
	DEFINE t Transport
	DEFINE ex Exception
	DEFINE sfex SendFailedException
	DEFINE mex MessagingException
	DEFINE i,i2 SMALLINT

	MAILDEBUG(2,"mailSmtpSend")

	IF smtp_session IS NULL THEN
		MAILDEBUG(-1,"smtp_session is NULL")
		RETURN FALSE
	END IF

	TRY
		LET msg = MimeMessage.create(smtp_session);
		MAILDEBUG(3,"mailSmtpSend, From:"||smtp_from)
		CALL msg.setFrom( InternetAddress.create( smtp_from ) )
-- ReplyTo
		LET replyTo = ia.create( 1 )
		LET replyTo[1] = InternetAddress.create( smtp_replyTo )
		CALL msg.setReplyTo( replyTo )

-- check for and remote null to,cc,bcc array elements.
		LET i2 = smtp_to.getLength()
		FOR i = i2 TO 1 STEP -1
			IF smtp_to[i] IS NULL THEN CALL smtp_to.deleteElement(i) END IF
		END FOR
		LET i2 = smtp_cc.getLength()
		FOR i = i2 TO 1 STEP -1
			IF smtp_cc[i] IS NULL THEN CALL smtp_cc.deleteElement(i) END IF
		END FOR
		LET i2 = smtp_bcc.getLength()
		FOR i = i2 TO 1 STEP -1
			IF smtp_bcc[i] IS NULL THEN CALL smtp_bcc.deleteElement(i) END IF
		END FOR

		IF smtp_to.getLength() > 0 THEN
			LET to_add = ia.create( smtp_to.getLength() )
			FOR i = 1 TO smtp_to.getLength()
				MAILDEBUG(3,"mailSmtpSend, To:"||NVL(smtp_to[i],"NULL")||" of "||smtp_to.getLength() )
				LET to_add[1] = InternetAddress.create(smtp_to[i])
			END FOR
			CALL msg.setRecipients(Message.RecipientType.TO, to_add)
			MAILDEBUG(3,"mailSmtpSend, To Set")
		ELSE
			RETURN FALSE
		END IF
		IF smtp_cc.getLength() > 0 THEN
			LET cc_add = ia.create( smtp_cc.getLength() )
			FOR i = 1 TO smtp_cc.getLength()
				LET cc_add[i] = InternetAddress.create(smtp_cc[i])
			END FOR
			CALL msg.setRecipients(Message.RecipientType.CC, cc_add)
		END IF
		IF smtp_bcc.getLength() > 0 THEN
			LET bcc_add = ia.create( smtp_bcc.getLength() )
			FOR i = 1 TO smtp_bcc.getLength()
				LET bcc_add[i] = InternetAddress.create(smtp_bcc[i])
			END FOR
			CALL msg.setRecipients(Message.RecipientType.BCC, bcc_add)
		END IF
		MAILDEBUG(3,"mailSmtpSend, subj:"||l_subj)
		CALL msg.setSubject(l_subj)
		MAILDEBUG(3,"mailSmtpSend, Date")
		CALL msg.setSentDate( java.util.Date.create() )
		-- If the desired charset is known, you can use
		-- setText(text, charset)
		IF smtp_attachements.getLength() > 0 THEN
			LET i =  smtp_attachements.getLength() + 1
			LET mbps = mbp.create( i )
			LET mp = MimeMultipart.create()
			MAILDEBUG(3,"mailSmtpSend, create a mimeBodyPart")
			LET mbps[1] = MimeBodyPart.create()
			MAILDEBUG(3,"mailSmtpSend, body:"||l_msg.trim()||"\ncharset:"||m_charset)
			CALL mbps[1].setText(l_msg, m_charset, l_texttype) 
			MAILDEBUG(3,"mailSmtpSend, adding attachements:"||smtp_attachements.getLength())
			FOR i = 1 TO smtp_attachements.getLength()
				LET mbps[i+1] = MimeBodyPart.create()
				LET l_file = ATTACH_OUT||os.Path.separator()||smtp_attachements[i]
				CALL mbps[i+1].attachFile( l_file )
			END FOR
			MAILDEBUG(3,"mailSmtpSend, adding mailBodyParts:"||mbps.getLength())
			FOR i = 1 TO mbps.getLength()
      	CALL mp.addBodyPart(mbps[i]);
      END FOR
			MAILDEBUG(3,"mailSmtpSend, Doing set content.")
			CALL msg.setContent( mp )
		ELSE
			MAILDEBUG(3,"mailSmtpSend, body:"||l_msg.trim()||":"||m_charset)
			CALL msg.setText(l_msg, m_charset, l_texttype)
		END IF
		CALL mailStatus(__LINE__,"mailSmtpSend getting transport object ...")
		LET t = smtp_session.getTransport("smtps")
		CALL mailStatus(__LINE__,"mailSmtpSend Connecting ...")
		MAILDEBUG(3,SFMT("connect('%1','%2','%3')",smtp_host, smtp_from, smtp_pass))
		CALL t.connect(smtp_host, smtp_from, smtp_pass)
		CALL mailStatus(__LINE__,"mailSmtpSend Sending ...")
		LET m_debugText = "mailStatus check"
		CALL t.sendMessage(msg, msg.getAllRecipients())
		LET m_debugText = "sendMessage call"
		RETURN TRUE
	CATCH
		MAILDEBUG(0,"--Exception handler!!--")
		LET ex = mex -- How do I set this to the exception !!!
		WHILE ex IS NOT NULL
			IF (ex INSTANCEOF javax.mail.SendFailedException) THEN
					LET sfex = CAST( ex AS SendFailedException)
					LET invalid = sfex.getInvalidAddresses()
					IF invalid IS NOT NULL THEN
						MAILDEBUG(0,"    ** Invalid Addresses")
						FOR i = 0 TO invalid.getLength()
							MAILDEBUG(0,"         "||invalid[i])
						END FOR
					END IF
				LET validUnsent = sfex.getValidUnsentAddresses()
				IF validUnsent IS NOT NULL THEN
					MAILDEBUG(3,"    ** Valid Unsent Addresses")
					FOR i = 0 TO validUnsent.getLength()
						MAILDEBUG(3,"         "||validUnsent[i])
					END FOR
				END IF
				LET validSent = sfex.getValidSentAddresses()
				IF (validSent IS NOT NULL) THEN
					MAILDEBUG(3,"    ** Valid Sent Addresses")
					FOR i = 0 TO validSent.getLength()
						MAILDEBUG(3,"         "||validSent[i])
					END FOR
				END IF
			END IF
			IF (ex INSTANCEOF javax.mail.MessagingException) THEN
				LET ex = mex.getNextException()
			END IF
		END WHILE
	END TRY
	RETURN FALSE
END FUNCTION
--------------------------------------------------------------------------------


-- Private Imapi Functions
--------------------------------------------------------------------------------
#+ Get tree structure of folders.
PRIVATE FUNCTION mailFolders(f, pi)
	DEFINE f Folder
	DEFINE folders ARRAY [] OF Folder
	DEFINE x, i, idx, pi SMALLINT
	DEFINE nam STRING

--	MAILDEBUG(3,"Folders:")
	LET folders = f.list()
	FOR i = 1 TO folders.getLength()
--		MAILDEBUG(3,i||" "||folders[i].getFullName())
		LET idx = mboxes.getLength() + 1
		LET mboxes[idx].id = idx
		LET mboxes[idx].pid= pi
		LET mboxes[idx].fullname = folders[i].getFullName()
		LET mboxes[idx].img = D_FLD_DEF
		LET nam = mboxes[idx].fullname
		LET x = nam.getIndexOf("/",1)
		IF x > 0 THEN LET nam = nam.subString(x+1,nam.getLength()) END IF
		LET mboxes[idx].name = nam
		CASE UPSHIFT(nam)
			WHEN "[GMAIL]" LET mboxes[idx].img = D_FLD_GMAIL
			WHEN "INBOX" LET mboxes[idx].img = D_FLD_INBOX
			WHEN "JUNK" LET mboxes[idx].img = D_FLD_JUNK
			WHEN "SPAM" LET mboxes[idx].img = D_FLD_JUNK
			WHEN "TRASH" LET mboxes[idx].img = D_FLD_DELETED
			WHEN "SENT" LET mboxes[idx].img = D_FLD_SENT
			WHEN "SENT MAIL" LET mboxes[idx].img = D_FLD_SENT
		END CASE
		CALL mailFolders( folders[i], idx )
	END FOR
	
END FUNCTION
--------------------------------------------------------------------------------
#+ Retrieve an Envelope for message no
#+
#+ @param mno Message No
#+ @param m Message ( java object )
PRIVATE FUNCTION mailRetvEnvelope(mno, m)
	DEFINE mno INTEGER
	DEFINE m Message
	DEFINE j, i SMALLINT
	DEFINE a ARRAY [] OF Address
	--DEFINE ia InternetAddress
	--DEFINE aa ARRAY [] OF InternetAddress
	DEFINE d java.util.Date
	DEFINE flags Flags
	DEFINE f Flags.Flag
	DEFINE sf ARRAY [] OF Flags.Flag
	DEFINE sb base.StringBuffer
	DEFINE s, subj STRING
	DEFINE uf ARRAY [] OF java.lang.String
	DEFINE hdrs ARRAY [] OF java.lang.String
	DEFINE df DateFormat
	DEFINE dfmt, colr, flag, flg_answered, flg_junk, flg_fjs STRING
	DEFINE mail_key INTEGER

	MAILDEBUG(3,"mailRetvEnvelope mno:"||mno)

	IF m IS NULL THEN
		MAILDEBUG(-1,"ERR:mailRetvEnvelope m IS NULL!")
		RETURN
	END IF

--	MAILDEBUG(3,"got past null check!")

-- SUBJECT
	TRY
		LET subj = m.getSubject()
		IF mno > 0 THEN LET mails[mno].subj =  subj	END IF
		MAILDEBUG(1,"mno:"||mno||":SUBJECT:"||subj)  -- not an error but I need it in the stderr list.
	CATCH
		MAILDEBUG(-1,"ERR: m.getSubject() Failed!!")
	END TRY

-- FLAGS - Check flags first to see if it's a mail that's already be processed.
	LET flags = m.getFlags()
	LET sb = base.StringBuffer.create()
	LET sf = flags.getSystemFlags() -- get the system flags

	LET flg_fjs = NULL
	LET flg_answered = ""
	LET flg_junk = D_JUNK
	LET colr = "black"
	FOR i = 1 TO sf.getLength()
		LET f = sf[i]
		CASE f
			WHEN javax.mail.Flags.Flag.ANSWERED
				LET s = "\\Answered"
				LET flg_answered = D_ANSWERED
				CONTINUE FOR
			WHEN javax.mail.Flags.Flag.DELETED
				LET s = "\\Deleted"
				LET colr = "cyan"
			WHEN javax.mail.Flags.Flag.DRAFT
				LET s = "\\Draft"
			WHEN javax.mail.Flags.Flag.FLAGGED
				LET s = "\\Flagged"
			WHEN javax.mail.Flags.Flag.RECENT
				LET s = "\\Recent"
			WHEN javax.mail.Flags.Flag.SEEN
				LET s = "\\Seen"
				LET colr = "blue"
				--CONTINUE FOR
			OTHERWISE
				LET s = "\\Unknown"
				CONTINUE FOR
		END CASE
		CALL sb.append(' '||s)
	END FOR

	LET uf = flags.getUserFlags() -- get the user flag strings
	FOR i = 1 TO uf.getLength()
		LET flag = uf[i]
		IF flag = "$label1" THEN LET colr = "red" END IF
		IF flag = "$label2" THEN LET colr = "yellow" END IF
		IF flag = "$label3" THEN LET colr = "green" END IF
		IF flag = "$label4" THEN LET colr = "magenta" END IF
		IF flag = "$Forwarded" THEN 
			IF flg_answered IS NULL THEN
				LET flg_answered = D_FORWARDED
			ELSE
				LET flg_answered = D_FORW_ANSW
			END IF
			CONTINUE FOR
		END IF
		IF flag = "NonJunk" THEN LET flg_junk = "" CONTINUE FOR END IF
		IF flag.subString(1,3) = MYFLAG THEN 
			LET flg_fjs = flag
			LET mail_key = flag.subString(4,flag.getLength())
		END IF

-- Remove all my tags while testing!!
		IF clr_flags AND mno > 0 AND flag.subString(1,1) != "$" THEN 
			CALL flags.remove(flag) 
			MAILDEBUG(0,"Flag: '"||flag||"' REMOVED")
			LET flg_fjs = NULL
			LET mail_key =  0
			CONTINUE FOR
		END IF

		CALL sb.append(' '||flag)
		MAILDEBUG(3,"Flag: '"||flag||"' "||colr)
	END FOR

	IF clr_flags AND mno > 0 THEN 
		CALL m_folder.setFlags(mno, mno, flags, FALSE ) 
		MAILDEBUG(3,"X FLAGS:"||sb.toString()||" sf:"||sf.getLength()||" uf:"||uf.getLength())
	ELSE
		MAILDEBUG(3,"FLAGS:"||sb.toString()||" sf:"||sf.getLength()||" uf:"||uf.getLength())
	END IF

	IF use_db AND mno > 0 THEN
		IF mailDBGetHead( m_mbox, mno, mail_key ) THEN RETURN END IF
		IF flg_fjs IS NOT NULL THEN
			CALL flags.remove(flg_fjs) -- because flag must be wrong because record not found in db.
			CALL m_folder.setFlags(mno, mno, flags, FALSE ) 
		END IF
	END IF

-- FROM 
	LET a = m.getFrom()
	IF a IS NOT NULL THEN
		FOR j = 1 TO a.getLength()
			MAILDEBUG(3,"FROM: " || a[j].toString())
		END FOR
		IF mno > 0 THEN LET mails[mno].from_whom = a[1].toString() END IF
	END IF

	IF mno > 0 THEN  CALL recps[ mno ].recp.clear() END IF
-- REPLY TO
	IF ((a = m.getReplyTo()) IS NOT NULL) THEN
		FOR j = 1 TO a.getLength()
			MAILDEBUG(3,"REPLY TO: " || a[j].toString())
			IF mno > 0 THEN 
				IF j = 1 THEN LET mails[mno].reply_to = a[1].toString() END IF
				LET recps[ mno ].recp[ recps[ mno ].recp.getLength() + 1 ].mode = "REPLYTO"
				LET recps[ mno ].recp[ recps[ mno ].recp.getLength() ].addr = a[j].toString()
			END IF
		END FOR
	END IF

-- DATE
	LET d = m.getSentDate()
	IF d IS NOT NULL THEN
		LET dfmt = d.getYear()+1900||"-"||d.getMonth()+1||"-"||d.getDate()||" "||d.getHours()||":"||d.getMinutes()||":"||d.getSeconds()
		IF mno > 0 THEN 
			--LET mails[mno].when = d.toString()
			LET df = java.text.DateFormat.getDateTimeInstance(DateFormat.SHORT, DateFormat.MEDIUM)
			LET mails[mno].when = df.format(d)
			LET mails[mno].when2 = EXTEND( dfmt, YEAR TO SECOND)
		END IF
		MAILDEBUG(3,"SendDate: " || d.toString()||" = "||dfmt ) --stdout
	ELSE
		MAILDEBUG(3,"SendDate: UNKNOWN")
	END IF

	IF use_db THEN 
		-- Need to see if this mail is already in DB
	END IF

-- TO
	LET a = m.getRecipients(Message.RecipientType.TO)
	IF a IS NOT NULL THEN
		FOR j = 1 TO a.getLength()
			MAILDEBUG(3,"TO: " || a[j].toString())
			{LET ia = CAST( a[j] AS InternetAddress )			
			IF (ia.isGroup()) THEN
				LET aa = ia.getGroup(false)
				FOR k = 0 TO aa.getLength()
					MAILDEBUG(3,"  GROUP: " || aa[k].toString())
				END FOR
			END IF	}
			IF mno > 0 THEN 
				IF j = 1 THEN LET mails[mno].to_whom= a[1].toString() END IF
				LET recps[ mno ].recp[ recps[ mno ].recp.getLength() + 1 ].mode = "To"
				LET recps[ mno ].recp[ recps[ mno ].recp.getLength() ].addr = a[j].toString()
			END IF
		END FOR
	END IF
-- CC
	LET a = m.getRecipients(Message.RecipientType.CC)
	IF a IS NOT NULL THEN
		FOR j = 1 TO a.getLength()
			MAILDEBUG(3,"CC: " || a[j].toString())
			{LET ia = CAST( a[j] AS InternetAddress )
			IF (ia.isGroup()) THEN
				LET aa = ia.getGroup(false)
				FOR k = 0 TO aa.getLength()
					MAILDEBUG(3,"  GROUP: " || aa[k].toString())
				END FOR
			END IF	}
			IF mno > 0 THEN 
				LET recps[ mno ].recp[ recps[ mno ].recp.getLength() + 1 ].mode = "CC"
				LET recps[ mno ].recp[ recps[ mno ].recp.getLength() ].addr = a[j].toString()
			END IF
		END FOR
	END IF
-- BCC
	LET a  = m.getRecipients(Message.RecipientType.BCC)
	IF a IS NOT NULL THEN
		FOR j = 1 TO a.getLength()
			MAILDEBUG(3,"BCC: " || a[j].toString())
			{LET ia = CAST( a[j] AS InternetAddress )
			IF (ia.isGroup()) THEN
				LET aa = ia.getGroup(false)
				FOR k = 0 TO aa.getLength()
					MAILDEBUG(3,"  GROUP: " || aa[k].toString())
				END FOR
			END IF	}
			IF mno > 0 THEN 
				LET recps[ mno ].recp[ recps[ mno ].recp.getLength() + 1 ].mode = "BCC"
				LET recps[ mno ].recp[ recps[ mno ].recp.getLength() ].addr = a[j].toString()
			END IF
		END FOR
	END IF

	IF mno > 0 THEN 
		LET mails[mno].flags = sb.toString()
		LET mails[mno].flg_junk = flg_junk
		LET mails[mno].flg_answered = flg_answered
		LET mails[mno].flg_fjs = flg_fjs
		LET colr_mails[mno].col1 = colr
		LET colr_mails[mno].col4 = colr
		LET colr_mails[mno].col5 = colr
		LET colr_mails[mno].col6 = colr
		LET colr_mails[mno].col7 = colr
		IF use_db THEN CALL mailDBHeadInsert(mno, m) END IF
	END IF

	-- X-MAILER
	LET hdrs = m.getHeader("X-Mailer")
	IF (hdrs IS NOT NULL) THEN
		MAILDEBUG(3,"X-Mailer: " || hdrs[1])
	ELSE
		MAILDEBUG(3,"X-Mailer NOT available")
	END IF

END FUNCTION
--------------------------------------------------------------------------------
#+ Retrieve a mail body part from the imapi server
#+
#+ @param p part object
#+ @param hk Header Serial number for DB record.
PRIVATE FUNCTION mailRetvPart(p, mno, hk, pno)
	DEFINE p Part
	DEFINE mno, hk INTEGER
	DEFINE pno SMALLINT
	DEFINE filename, localname, f_ns STRING
	DEFINE ct, j_ns java.lang.String
	DEFINE nct ContentType
	DEFINE mp Multipart
	DEFINE o Object
	DEFINE inpstr InputStream
	DEFINE disp,descr STRING
	DEFINE i SMALLINT
	DEFINE done BOOLEAN
	DEFINE mm MimeMessage

	MAILDEBUG(3,"Info:"||mno||":"||pno||":mailRetvPart")

	IF sb_emailBody IS NULL THEN
		LET sb_emailBody = base.Stringbuffer.create()
	END IF
	IF sb_emailHTMLBody IS NULL THEN
		LET sb_emailHTMLBody = base.Stringbuffer.create()
	END IF

	IF (p INSTANCEOF Message) THEN 
		MAILDEBUG(3,"Info:"||mno||":"||pno||": is a message.")
		-- don't need to because it's already be called when reading headers.
		--CALL mailRetvEnvelope(0, CAST( p AS Message) )
	ELSE
		MAILDEBUG(3,"Info:"||mno||":"||pno||": is NOT a message.")
	END IF

	MAILDEBUG(3,"Info:"||mno||":"||pno||":Size:"||p.getSize())
	MAILDEBUG(3,"Info:"||mno||":"||pno||":LineCount:"||p.getLineCount())
	TRY
		LET descr = p.getDescription()
		IF descr IS NULL THEN LET descr = "(null)" END IF
	CATCH
		LET descr = "failed to getDescription"
	END TRY
	MAILDEBUG(3,"Info:"||mno||":"||pno||":Description:"||descr)

	MAILDEBUG(3,"Info:"||mno||":"||pno||":----- checking contentType ------")
	LET done = FALSE
	TRY
		LET ct = p.getContentType()
	CATCH
		MAILDEBUG(-1,"ERR:"||mno||":"||pno||":Problem doing getContentType from Message!")
		TRY
			LET mm = CAST( p AS MimeMessage )
			LET p = javax.mail.internet.MimeMessage.create(mm);
		CATCH
			MAILDEBUG(-1,"ERR: Getting MimeMessage number: " ||mno||" Failed!")
		END TRY
		TRY
		 	LET ct = p.getContentType()
		CATCH
			MAILDEBUG(-1,"ERR:"||mno||":"||pno||":Problem doing getContentType from mimeMessage!")
			RETURN FALSE
		END TRY
	END TRY
	LET m_mime_type = ct
	MAILDEBUG(3,"Info:"||mno||":"||pno||":m_mime_type: " || m_mime_type )
	TRY
		LET nct = ContentType.create( ct )
		MAILDEBUG(3,"Info:"||mno||":"||pno||":CONTENT-TYPE: " || nct.toString() )
	CATCH
		MAILDEBUG(-1,"ERR:"||mno||":"||pno||":BAD CONTENT-TYPE: " || ct)
	END TRY

	LET filename = p.getFileName()
	IF filename IS NOT NULL THEN
		MAILDEBUG(3,"Info:"||mno||":"||pno||":FILENAME: " || filename)
	ELSE
		MAILDEBUG(3,"Info:"||mno||":"||pno||":No FileName for this part.")
	END IF

	LET emailBodyHTML = FALSE
-- Using isMimeType to determine the content type avoids
-- fetching the actual content data until we need it.
	IF (p.isMimeType("text/plain")) THEN
		MAILDEBUG(3,"Info:"||mno||":"||pno||":This is plain text")
		--LET done = TRUE
	END IF
	IF (p.isMimeType("text/html")) THEN
		MAILDEBUG(3,"Info:"||mno||":"||pno||":This is html")
		LET emailBodyHTML = TRUE
		--LET done = TRUE
	END IF
	IF (p.isMimeType("multipart/*")) THEN
		TRY
			LET mp = CAST(p.getContent() AS Multipart )
			MAILDEBUG(3,"Info:"||mno||":"||pno||":This is a Multipart:"||m_level||" mp:"||mp.getCount())
		CATCH
			MAILDEBUG(-1,"ERR:"||mno||":"||pno||":Multipart:"||m_level||" Failed!")
			RETURN FALSE
		END TRY
		LET m_level = m_level + 1
		FOR i = 0 TO mp.getCount() - 1
			IF mailRetvPart(mp.getBodyPart(i), mno, hk, pno+1) THEN
			END IF
		END FOR
		LET m_level = m_level - 1
		LET done = TRUE
	END IF
	IF (p.isMimeType("message/rfc822")) THEN
		MAILDEBUG(3,"Info:"||mno||":"||pno||":This is a Nested Message:"||m_level)
		LET m_level = m_level + 1
		IF mailRetvPart( CAST(p.getContent() AS javax.mail.Part ), mno, hk, pno+1 ) THEN
		END IF
		LET m_level = m_level - 1
		LET done = TRUE
	END IF

	LET m_bodyPart = ""
	LET m_mime_type = ct
	IF m_level = 0 THEN
		LET mails[mno].content_type = ct
	END IF

-- Fetch it and check its Java type.
	LET o = p.getContent()
	IF o IS NULL THEN
		MAILDEBUG(3,"Info:"||mno||":"||pno||":o IS NULL!!")
	END IF
	CASE
		WHEN (o INSTANCEOF String)
			MAILDEBUG(3,"Info:"||mno||":"||pno||":This is a string")
			LET j_ns = CAST( o AS java.lang.String )
			LET f_ns = j_ns
			MAILDEBUG(3,"Info:"||mno||":"||pno||":Length="||j_ns.length())
			IF emailBodyHTML THEN
				CALL sb_emailHTMLBody.append( f_ns )
			ELSE
				CALL sb_emailBody.append( f_ns )
			END IF
			LET m_bodyPart = f_ns
			MAILDEBUG(3,"Info:"||mno||":"||pno||":StrBuf - txt:"||sb_emailBody.getLength()||" html:"||sb_emailHTMLBody.getLength())
			IF f_ns.getLength() > 0 THEN LET done = TRUE END IF
		WHEN (o INSTANCEOF InputStream)
			MAILDEBUG(3,"Info:"||mno||":"||pno||":This is an input stream")
			LET inpstr = CAST( o AS InputStream )
--			IF saveAttachments THEN
--				CALL mailSaveAtt(filename, hk, javax.mail.internet.MimeBodyPart.create( inpstr ) ) RETURNING localName
--			END IF
--		LET done = TRUE
		OTHERWISE
			MAILDEBUG(0,"Info:"||mno||":"||pno||":This is an unknown type")
			MAILDEBUG(0,o.toString())
	END CASE

	MAILDEBUG(3,"Info:"||mno||":"||pno||":lv:"||m_level||":---------------------------")

-- If we're saving attachments, write out anything that
-- looks like an attachment into an appropriately named
-- file.
	IF NOT done {AND m_level != 0} AND NOT p.isMimeType("multipart/*") THEN
		LET	disp = p.getDisposition()
		IF disp IS NULL THEN
			MAILDEBUG(3,"Info:"||mno||":"||pno||":lv:"||m_level||":disp IS NULL")
		ELSE
			IF disp.equalsIgnoreCase(Part.ATTACHMENT) THEN
				MAILDEBUG(3,"Info:"||mno||":"||pno||":lv:"||m_level||":disp = Part.ATTACHMENT")
			END IF
			IF disp.equalsIgnoreCase(Part.INLINE) THEN
				MAILDEBUG(3,"Info:"||mno||":"||pno||":lv:"||m_level||":disp = Part.INLINE")
			END IF
		END IF
-- many mailers don't include a Content-Disposition
		IF {(disp IS NULL OR disp.equalsIgnoreCase(Part.ATTACHMENT)) AND} saveAttachments THEN
			CALL mailSaveAtt(filename, hk, CAST(p AS MimeBodyPart) ) RETURNING localName
			IF mno > 0 THEN LET mails[mno].flg_attach = D_ATTACH END IF
		ELSE
			MAILDEBUG(3,"Info:"||mno||":"||pno||":lv:"||m_level||":-Else 1")
		END IF
	ELSE
		MAILDEBUG(3,"Info:"||mno||":"||pno||":lv:"||m_level||":-Else 2")
	END IF

	IF use_db AND hk > 0 THEN
		CALL mailDBBodyInsert(hk, filename, localName)
	END IF
	RETURN TRUE
END FUNCTION
--------------------------------------------------------------------------------
FUNCTION mailSaveAtt(fn, hk, mbp)
	DEFINE fn, ln, sn STRING
	DEFINE hk INTEGER
	DEFINE f File
	DEFINE mbp MimeBodyPart

	IF (fn IS NULL) THEN
		LET m_attnum = m_attnum + 1
		LET fn = "Attachment"||m_attnum
	END IF
	IF hk > 0 THEN
		LET ln = (hk USING "&&&&&&&&")||"-"||(m_partNo USING "&&&&")||".att"
	ELSE
		LET ln = fn
	END IF
	LET sn = os.path.join(m_attpath,ln)
	MAILDEBUG(3,"Saving attachment "||fn||" to file "||sn)
	TRY
		LET f = File.create(sn)
		IF (f.exists()) THEN
		-- XXX - could try a series of names
		--throw new IOException("file exists")
		END IF
		CALL mbp.saveFile(f)
	CATCH
		MAILDEBUG(-1,"ERR:Failed to save attachment!")
	END TRY
	RETURN ln
END FUNCTION
--------------------------------------------------------------------------------

-- DB Functions.

#+ Create the tables for storing the emails.
PUBLIC FUNCTION mailDBcreateTables()
	DEFINE tname STRING

	LET tname = "imapi_folders"
	CALL drop_tab( tname )
	TRY
		CREATE TABLE imapi_folders (
			account VARCHAR(50),
			dispname VARCHAR(40),
			origname VARCHAR(60),
			icon VARCHAR(20),
			id SMALLINT,
			pid SMALLINT,
			no_mails INTEGER,
			unread INTEGER
		)
		MAILDEBUG(3,"Created:"||tname)
	CATCH
		MAILDEBUG(-1,"ERR:Create '"||tname||"' failed:"||SQLERRMESSAGE)
	END TRY

	LET tname = "imapi_mail_header"
	CALL drop_tab( tname )
	TRY
		CREATE TABLE imapi_mail_header (
			head_key SERIAL,
			D_EMAILHEADER
		)
		MAILDEBUG(3,"Created:"||tname)
	CATCH
		MAILDEBUG(-1,"ERR:Create '"||tname||"' failed:"||SQLERRMESSAGE)
	END TRY

	LET tname = "imapi_mail_recp"
	CALL drop_tab( tname )
	TRY
		CREATE TABLE imapi_mail_recp (
			head_key INTEGER,
			mode VARCHAR(10),
			email_addr VARCHAR(200)
		)
		MAILDEBUG(3,"Created:"||tname)
	CATCH
		MAILDEBUG(-1,"ERR:Create '"||tname||"' failed:"||SQLERRMESSAGE)
	END TRY


	LET tname ="imapi_mail_bodypart"
	CALL drop_tab( tname )
	TRY
		CREATE TABLE imapi_mail_bodypart (
			body_key SERIAL,
			D_EMAILBODYPART
		)
		MAILDEBUG(3,"Created:"||tname)
	CATCH
		MAILDEBUG(-1,"ERR:Create '"||tname||"' failed:"||SQLERRMESSAGE)
	END TRY

END FUNCTION
--------------------------------------------------------------------------------
#+ Drop table
#+
#+ @param t table name
PRIVATE FUNCTION drop_tab(t)
	DEFINE t STRING
	DEFINE s VARCHAR(200)
	
	LET s = "DROP TABLE "||t
	TRY
		PREPARE p FROM s
		EXECUTE p
		MAILDEBUG(3,"Dropped "||t)
	CATCH
-- Don't care.
	END TRY
END FUNCTION
--------------------------------------------------------------------------------
#+ Populate the folder array from DB
FUNCTION mailDBinit(l_user)
	DEFINE l_user VARCHAR(50)
	DEFINE l_fld RECORD 
			account VARCHAR(50),
			dispname VARCHAR(40),
			origname VARCHAR(60),
			icon VARCHAR(20),
			id SMALLINT,
			pid SMALLINT,
			no_mails INTEGER,
			unread INTEGER
		END RECORD

	LET m_user = l_user

	MAILDEBUG(3,"mailDBinit")

-- Fetch the folder list
	DECLARE f CURSOR FOR SELECT * FROM imapi_folders WHERE account = l_user
		ORDER BY id,pid
	FOREACH f INTO l_fld.*
		MAILDEBUG(3,"mailDBinit:"||l_fld.origname)
		LET mboxes[ mboxes.getLength() + 1 ].fullname = l_fld.origname
		LET mboxes[ mboxes.getLength() ].name = l_fld.dispname
		LET mboxes[ mboxes.getLength() ].img = l_fld.icon
		LET mboxes[ mboxes.getLength() ].pid = l_fld.pid
		LET mboxes[ mboxes.getLength() ].id = l_fld.id
	END FOREACH

END FUNCTION
--------------------------------------------------------------------------------
#+ Fetch the mail body for this mail number.
FUNCTION mailDBretv(mno)
	DEFINE mno INTEGER
	DEFINE mh RECORD
			head_key INTEGER,
			D_EMAILHEADER
		END RECORD
	DEFINE mb RECORD
			body_key INTEGER,
			D_EMAILBODYPART
		END RECORD
	DEFINE mbox VARCHAR(40)
	DEFINE mt STRING
	DEFINE x SMALLINT

	LET mbox = UPSHIFT(m_mbox)
	IF mails[ mno ].head_key IS NULL OR mails[ mno ].head_key < 1 THEN
		--SELECT * INTO mh.* FROM imapi_mail_header WHERE account = m_user
		--	AND foldername = mbox	AND message_no = mno
		--IF STATUS = NOTFOUND THEN
			MAILDEBUG(-1,"ERR:mailDBretv: No HEADKEY!")
			RETURN FALSE
		--END IF
	ELSE
		LET mh.head_key = mails[ mno ].head_key
	END IF

	MAILDEBUG(2,"mailDBretv:"||mno||":"||mbox||" HEADKEY:"||mh.head_key)

	LET emailBody = NULL
	LET emailHTMLBody = NULL

	LOCATE mb.mbody IN MEMORY
	DECLARE mbc CURSOR FOR
		SELECT * FROM imapi_mail_bodypart WHERE head_key = mh.head_key
			AND mime_type[1,4] = "TEXT"
		ORDER BY part_no
	FOREACH mbc INTO mb.*
		IF mb.mime_type IS NULL THEN LET mb.mime_type = "(null)" END IF
		LET mt = UPSHIFT(mb.mime_type)
		MAILDEBUG(3,"mailDBretv:"||mb.part_no||":"||mt||" mb:"||mb.mbody.getLength())
		LET x = mt.getIndexOf("NAME=",8)
		IF x > 0 THEN CONTINUE FOREACH END IF
		IF UPSHIFT(mb.mime_type[1,4]) = "TEXT" AND mb.mbody.getLength() > 0 THEN
			LET emailBodyHTML = FALSE
			IF UPSHIFT(mb.mime_type[1,10]) MATCHES "*HTML*" THEN
				LET emailBodyHTML = TRUE
			END IF
			IF emailBodyHTML THEN
				IF emailHTMLBody IS NULL THEN
					LET emailHTMLBody = mb.mbody
				ELSE
					LET emailHTMLBody = emailHTMLBody||"\n\n<HR>\n"||mb.mbody
				END IF
			ELSE
				IF emailBody IS NULL THEN
					LET emailBody = mb.mbody
				ELSE
					LET emailBody = emailBody||"\n\n--\n"||mb.mbody
				END IF
			END IF
		END IF
		MAILDEBUG(3,"mailDBretv:"||mb.part_no||":"||(mb.mime_type[1,10])||" f:"||emailBodyHTML||" mb:"||mb.mbody.getLength()||" eb:"||emailBody.getLength()||" ehb:"||emailHTMLBody.getLength())
	END FOREACH
	MAILDEBUG(2,"mailDBretv:"||mno||":"||mbox||" Done")
	RETURN TRUE

END FUNCTION
--------------------------------------------------------------------------------
#+ Fetch mail headers for this folder.
FUNCTION mailDBFetch(mbox)
	DEFINE mbox VARCHAR(50)
	DEFINE mh RECORD
			head_key INTEGER,
			D_EMAILHEADER
		END RECORD
	DEFINE mno INTEGER

	CALL mails.clear()
	LET mbox = UPSHIFT(mbox)
	MAILDEBUG(3,"mailDBFetch:"||m_mbox||":"||m_user)
	DECLARE mf CURSOR FOR SELECT * FROM imapi_mail_header WHERE account = m_user
		AND foldername = mbox
		ORDER BY message_no 
	LET mno = 0
	FOREACH mf INTO mh.*
		LET mno = mno + 1
		MAILDEBUG(3,"mailDBFetch:"||mno||":"||mh.subject)
		CALL mailDBSetHead( mno, mh.* )
	END FOREACH

END FUNCTION
--------------------------------------------------------------------------------
#+ Set mail header for this DB mail record
FUNCTION mailDBGetHead(mbox, mno, mail_key)
	DEFINE mbox VARCHAR(50)
	DEFINE mno, mail_key INTEGER
	DEFINE mh RECORD
			head_key INTEGER,
			D_EMAILHEADER
		END RECORD

	LET mbox = UPSHIFT(mbox)

	IF mail_key IS NOT NULL AND mail_key > 0 THEN
		SELECT * INTO mh.* FROM imapi_mail_header WHERE head_key = mail_key
		IF STATUS = NOTFOUND THEN
			MAILDEBUG(3,"mailDBGetHead mail_key:"||mail_key||" Not found")
			RETURN FALSE
		ELSE
			IF mbox != mh.foldername THEN
				LET mh.foldername = mbox
				UPDATE imapi_mail_header SET foldername = mbox WHERE head_key = mail_key
			END IF
			MAILDEBUG(3,"mailDBGetHead mail_key:"||mail_key||":"||mh.subject)
			CALL mailDBSetHead( mno, mh.* )
			RETURN TRUE
		END IF
	END IF
	MAILDEBUG(3,"mailDBGetHead not found because key is null or 0")
	RETURN FALSE
END FUNCTION
--------------------------------------------------------------------------------
#+ Set mail header for this DB mail record
FUNCTION mailDBSetHead(mno, mh)
	DEFINE mno INTEGER
	DEFINE mh RECORD
			head_key INTEGER,
			D_EMAILHEADER
		END RECORD

	IF mno < 1 OR mno > mails.getLength() THEN
		MAILDEBUG(-1,"ERR:mailDBSetHead mno:"||mno||" invalid")
		RETURN
	END IF
	MAILDEBUG(3,"mailDBSetHead mno:"||mno||": HEAD KEY:"||mh.head_key)
	LET mails[ mno ].head_key = mh.head_key
	LET mails[ mno ].subj = mh.subject
	LET mails[ mno ].from_whom = mh.h_from
	LET mails[ mno ].to_whom = mh.h_to
	LET mails[ mno ].reply_to = mh.h_reply_to
	LET mails[ mno ].when = mh.senddate
	LET mails[ mno ].when2 = mh.senddatetime
	LET mails[ mno ].flags = mh.flags
	LET mails[ mno ].content_type = mh.content_type
	LET mails[ mno ].flg_fjs = "Processed"
	IF mh.flg_answered = 1 THEN LET mails[ mno ].flg_answered = D_ANSWERED END IF
	IF mh.flg_answered = 2 THEN LET mails[ mno ].flg_answered = D_FORWARDED END IF
	IF mh.flg_answered = 3 THEN LET mails[ mno ].flg_answered = D_FORW_ANSW END IF
	IF mh.flg_junk THEN LET mails[ mno ].flg_junk = D_JUNK END IF
	IF mh.flg_attach THEN LET mails[ mno ].flg_attach = D_ATTACH END IF

END FUNCTION
--------------------------------------------------------------------------------
#+ Insert a mail into the DB
PRIVATE FUNCTION mailDBHeadInsert(mno, m)
	DEFINE mno INTEGER
	DEFINE m Message
	DEFINE mh RECORD
			head_key INTEGER,
			D_EMAILHEADER
		END RECORD
	DEFINE x SMALLINT
	DEFINE vc_addr VARCHAR(100)
	DEFINE vc_mode VARCHAR(20)

	MAILDEBUG(3,"mailDBHeadInsert mno:"||mno||":"||m_mbox||":"||m_user)

	LET mh.account = m_user
	LET mh.message_no = mno
	LET mh.foldername = UPSHIFT(m_mbox)
	LET mh.subject = mails[ mno ].subj
{ This is not possible because a reply can match a previous reply!!!
	SELECT head_key INTO mh.head_key FROM imapi_mail_header 
	WHERE account = mh.account
		AND foldername = mh.foldername
		AND message_no = mh.message_no 
		AND subject = mh.subject
	IF STATUS != NOTFOUND THEN
		LET mails[ mno ].head_key = mh.head_key
		MAILDEBUG(3,"mailDBHeadInsert mno:"||mno||": HEAD KEY:"||mh.head_key||" EXISTED!")
		RETURN
	END IF
}
	LET mh.head_key = 0
	LET mh.h_from = mails[ mno ].from_whom
	LET mh.h_to = mails[ mno ].to_whom
	LET mh.h_reply_to = mails[ mno ].reply_to
	LET mh.senddate = mails[ mno ].when
	LET mh.senddatetime = mails[ mno ].when2
	LET mh.flags = mails[ mno ].flags

	LET mh.flg_answered = FALSE
	LET mh.flg_junk = FALSE
	LET mh.flg_attach = FALSE
	IF mails[ mno ].flg_answered = D_ANSWERED THEN LET mh.flg_answered = 1 END IF
	IF mails[ mno ].flg_answered = D_FORWARDED THEN LET mh.flg_answered = 2 END IF
	IF mails[ mno ].flg_answered = D_FORW_ANSW THEN LET mh.flg_answered = 3 END IF
	IF mails[ mno ].flg_junk IS NOT NULL THEN LET mh.flg_junk = TRUE END IF
	IF mails[ mno ].flg_attach IS NOT NULL THEN LET mh.flg_attach = TRUE END IF
	INSERT INTO imapi_mail_header VALUES( mh.* )

	LET mh.head_key = SQLCA.sqlerrd[2]
	CALL mailSetFlag(mno, MYFLAG||(mh.head_key USING "&&&&&&&&&"))
	LET mails[ mno ].head_key = mh.head_key
	MAILDEBUG(3,"mailDBHeadInsert mno:"||mno||": HEAD KEY:"||mh.head_key||" INSERTED")

	FOR x = 1 TO recps[ mno ].recp.getLength()
		LET vc_addr = recps[ mno ].recp[x].addr
		LET vc_mode = recps[ mno ].recp[x].mode
		INSERT INTO imapi_mail_recp VALUES(mh.head_key, vc_mode, vc_addr )
	END FOR

	LET m_partNo = 0
	LET m_level = 0
	IF sb_emailBody IS NULL THEN
		LET sb_emailBody = base.Stringbuffer.create()
	ELSE
		CALL sb_emailBody.clear()
	END IF
	IF sb_emailHTMLBody IS NULL THEN
		LET sb_emailHTMLBody = base.Stringbuffer.create()
	ELSE
		CALL sb_emailHTMLBody.clear()
	END IF
	IF NOT mailRetvPart(m, mno, mh.head_key, 0 ) THEN RETURN END IF -- Fetch mail body.
	LET mh.content_type = mails[ mno ].content_type
	IF mails[ mno ].flg_attach IS NOT NULL THEN LET mh.flg_attach = TRUE END IF
	MAILDEBUG(3,"mailDBHeadInsert - head update flg_attach:"||mh.flg_attach)
	UPDATE imapi_mail_header SET ( flg_attach, content_type ) =
													( mh.flg_attach, mh.content_type ) 
		WHERE head_key = mh.head_key

END FUNCTION
--------------------------------------------------------------------------------
#+ Insert a mail into the DB
#+ @param hk Head Key
#+ @param fn Filename
#+ @param ln LocalName
PRIVATE FUNCTION mailDBBodyinsert(hk, fn, ln)
	DEFINE hk INTEGER
	DEFINE fn, ln STRING
	DEFINE mb RECORD
			body_key INTEGER,
			D_EMAILBODYPART
		END RECORD
	DEFINE myStr base.StringBuffer

	IF fn IS NULL THEN LET fn = "(null)" END IF
	IF ln IS NULL THEN LET ln = "(null)" END IF
	MAILDEBUG(3,"mailDBodyInsert:"||hk||":"||m_partNo||":"||m_bodyPart.getLength()||" fn:"||fn||" ln:"||ln||" len:"|| m_bodyPart.getLength())

-- Must insert to create the attachedment record.
--	IF m_bodyPart.getLength() < 1 THEN RETURN END IF

	LOCATE mb.mbody IN MEMORY
	LET myStr = base.StringBuffer.create()
	CALL myStr.clear()
	CALL myStr.append( m_bodyPart )
	LET mb.head_key = hk
	LET mb.part_no = m_partno
	LET mb.filename = fn
	LET mb.localname = ln
	LET mb.mime_type = m_mime_type
	LET mb.body_key = 0
	LET mb.mbody = myStr.toString()
	INSERT INTO imapi_mail_bodypart VALUES( mb.* )

	LET m_partNo = m_partNo + 1

END FUNCTION
--------------------------------------------------------------------------------
#+ Retrieve the current charset
PRIVATE FUNCTION getCharset()
	DEFINE l STRING
	DEFINE c base.Channel

	LET c = base.Channel.create()
	CALL c.openPipe("fglrun -i mbcs 2>&1", "r")
	LET l = c.readLine()
	WHILE l IS NOT NULL
		IF l MATCHES "Charmap      : *" THEN
			RETURN l.subString(16,length(l))
			EXIT WHILE
		END IF
		LET l = c.readLine()
	END WHILE
	RETURN "UTF-8" -- maybe not a good default because I don't think we actual support utf-8 yet!
END FUNCTION
--------------------------------------------------------------------------------
#+ simple output for statebar message.
PRIVATE FUNCTION mailStatus(line, msg )
	DEFINE line SMALLINT
	DEFINE msg STRING
	IF GUI THEN
		MESSAGE msg
		CALL ui.Interface.refresh()
	END IF
	IF msg IS NULL THEN
		CALL logDebug( line, __FILE__, 1, "NULL!")
	ELSE
		CALL logDebug( line, __FILE__, 1, msg )
	END IF
END FUNCTION
