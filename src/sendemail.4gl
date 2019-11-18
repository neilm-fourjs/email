#+ SendEmail program - Send mail out.
#+ $Id: sendemail.4gl 983 2012-10-25 09:43:13Z  $

# fglrun sendGmail.42r neilm@4js.com test "A Test Email"

--TODO: Handle/detach multiple recipients!!

IMPORT os
IMPORT FGL libMailLog
IMPORT FGL sendmail
&define GL_DBGMSG( lev, msg ) \
 CALL logDebug( __LINE__, __FILE__, lev, NVL(msg,"NULL!"))

---------------------------------------------------------------------------------
#+ ARG_VAL(1) = email address
#+ ARG_VAL(2) = subject
#+ ARG_VAL(3) = body
#+
MAIN --{{{
	DEFINE l_email STRING
	DEFINE l_subj STRING
	DEFINE l_body, l_cp STRING
	DEFINE l_recipients DYNAMIC ARRAY OF RECORD
		mode STRING,
		recipient STRING
	END RECORD
	DEFINE l_attachments DYNAMIC ARRAY OF STRING
	DEFINE l_ret SMALLINT

	DISPLAY "CLASSPATH:", fgl_getenv("CLASSPATH")

	IF fgl_getEnv("STUDIO") = 1 THEN
		CALL startlog(base.Application.getProgramName() || ".s.log")
	ELSE
		CALL startlog(base.Application.getProgramName() || ".log")
	END IF

	LET libMailLog.m_debugLevel = 3
	LET libMailLog.m_debugFile = TRUE
	LET libMailLog.m_logName = "sendmail"
	LET libMailLog.m_path = "../logs/"

	LET l_email = ARG_VAL(1)
	LET l_subj = ARG_VAL(2)
	LET l_body = ARG_VAL(3)

	IF l_email.getLength() < 2 THEN
		GL_DBGMSG(0, CURRENT || ":No Email address passed")
		EXIT PROGRAM
	END IF
	IF l_subj.getLength() < 2 THEN
		GL_DBGMSG(0, CURRENT || ":No subject passed")
		EXIT PROGRAM
	END IF
	IF l_body.getLength() < 2 THEN
		GL_DBGMSG(0, CURRENT || ":No body passed")
		EXIT PROGRAM
	END IF

	LET l_cp = fgl_getEnv("CLASSPATH")
	IF l_cp.getLength() < 2 THEN
		GL_DBGMSG(0, CURRENT || ":No Class Path")
		EXIT PROGRAM
	END IF

	IF NOT os.Path.exists(l_cp) THEN
		GL_DBGMSG(0, CURRENT || ":No Java found at ClassPath:" || l_cp)
		EXIT PROGRAM
	END IF

	GL_DBGMSG(0, CURRENT || "EMAIL:" || l_email || " SUBJ:" || l_subj)

	LET l_recipients[1].mode = "TO"
	LET l_recipients[1].recipient = l_email
	CALL l_attachments.clear()

	--DISPLAY "Sending mail to ",g_recipients[1].recipient," Subject:",l_subj

	LET l_ret =
			sendmail.sendmail(
					l_recipients, l_attachments, l_subj, l_body, "plain", TRUE)
	EXIT PROGRAM l_ret
END MAIN
