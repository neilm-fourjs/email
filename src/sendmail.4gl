#+ Functions to send an email via smtp
#+ Based on $FGLDIR/demo/Mutlidialogs/Mailer.4gl
#+ $Id: sendmail.4gl 983 2012-10-25 09:43:13Z  $

#+
#+ This reads mailer.cnf to get the configuration of the smtp server.
#+ This host|smtp host|smtp port|from|timeout
#+ 10.2.0.1|10.2.0.1|25|support@4js-emea.com|10|

IMPORT os
IMPORT util
IMPORT FGL libMail
IMPORT FGL libMailLog
IMPORT FGL gen_lib

CONSTANT REPLY_TO = "my@gmail.co.uk"
&define GL_DBGMSG( lev, msg ) \
 CALL logDebug( __LINE__, __FILE__, lev, NVL(msg,"NULL!"))

DEFINE m_mailSmtpInit BOOLEAN

--------------------------------------------------------------------------------
#+ Main sendmail function
#+
#+ @param l_recipients Array of recipients
#+ @param l_attachements Array of attachments.
#+ @param l_subject Subject string
#+ @param l_mailtext Mail text string
#+ @param l_texttype Text type H=html P=plain
#+ @param l_confirm boolean
#+
#+ @return true/false
FUNCTION sendmail(
		l_recipients, l_attachements, l_subject, l_mailtext, l_texttype,
		l_confirm) --{{{
	DEFINE l_recipients DYNAMIC ARRAY OF RECORD
		mode STRING,
		recipient STRING
	END RECORD
	DEFINE l_attachements DYNAMIC ARRAY OF STRING
	DEFINE l_subject, l_mailtext, l_texttype STRING
	DEFINE l_confirm, x SMALLINT
	DEFINE l_host, l_from, l_pass STRING
	DEFINE l_cfg_xml om.domNode
	DEFINE l_file STRING

	GL_DBGMSG(1, "sendmail-To:" || NVL(l_recipients[1].recipient, "No Recipient1") || " Subj:" || NVL(l_subject, "subject=null"))

	IF NOT m_mailSmtpInit THEN
		LET l_file = fgl_getEnv("EMAILCFG")
		IF l_file.getLength() < 2 THEN
			LET l_file = os.path.join("..", "etc")
			LET l_file = os.path.join(l_file, "email.xcf")
		END IF
		LET l_cfg_xml = gen_lib.cfgRead(l_file)
		IF l_cfg_xml IS NULL THEN
			GL_DBGMSG(0, "Error reading email.xcf - Email not sent!!!!")
			RETURN FALSE
		END IF
		LET l_host = cfgFetch("SmtpHost", l_cfg_xml)
		LET l_from = cfgFetch("SmtpUser", l_cfg_xml)
		LET l_pass = cfgFetch("SmtpPass", l_cfg_xml)
		IF NOT mailSmtpinit(l_host, l_from, l_pass, REPLY_TO, FALSE) THEN
			GL_DBGMSG(0, "Error in mailSmtpinit - Email not sent!!!!")
			RETURN FALSE
		END IF
		LET m_mailSmtpInit = TRUE
	END IF

	CALL libMail.smtp_to.clear()
	CALL libMail.smtp_cc.clear()
	CALL libMail.smtp_bcc.clear()
	FOR x = 1 TO l_recipients.getLength()
		CASE UPSHIFT(l_recipients[x].mode)
			WHEN "TO"
				LET libMail.smtp_to[smtp_to.getLength() + 1] = l_recipients[x].recipient
			WHEN "CC"
				LET libMail.smtp_cc[smtp_cc.getLength() + 1] = l_recipients[x].recipient
			WHEN "BCC"
				LET libMail.smtp_bcc[smtp_bcc.getLength() + 1] =
						l_recipients[x].recipient
		END CASE
	END FOR
	FOR x = 1 TO l_attachements.getLength()
		IF l_attachements[x].getLength() > 1 THEN
			LET libMail.smtp_attachements[libMail.smtp_attachements.getLength() + 1] =
					l_attachements[x]
		END IF
	END FOR

	RETURN mailSmtpSend(l_subject, l_mailtext, l_texttype)

END FUNCTION
