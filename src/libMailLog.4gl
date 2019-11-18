#+ Logging messages to a debug file.
#+
#+ This module initially written by: Neil J.Martin ( neilm@4js.com )
#+
#+ Code should be self-documenting:
#+ -Comments should be avoided whenever possible.
#+ -Comments duplicate work when both writing and reading code.
#+ -If you need to comment something to make it understandable it should probably be rewritten.
#+
IMPORT os
IMPORT JAVA java.lang.System

PUBLIC DEFINE m_debugLevel SMALLINT
PUBLIC DEFINE m_debugFile BOOLEAN
PUBLIC DEFINE m_path STRING
PUBLIC DEFINE m_logName STRING

PRIVATE DEFINE m_debugOut base.channel

PUBLIC FUNCTION logDebug(line, file, lev, msg)
	DEFINE line INTEGER
	DEFINE file STRING
	DEFINE lev SMALLINT
	DEFINE msg, jmsg STRING
	DEFINE l_time CHAR(8)

	IF m_debugLevel IS NULL THEN
		LET m_debugLevel = 3
	END IF
	IF lev > m_debugLevel THEN
		RETURN
	END IF

	LET l_time = TIME
	LET file = os.path.basename(file)
	LET file = os.path.rootname(file)
	IF msg IS NULL THEN
		LET msg = "(null)"
	END IF
	LET msg = (line USING "<<&&&&") || ":" || file || ":" || msg
	IF lev < 0 THEN
		LET jmsg = l_time, ":", msg
		CALL System.err.println(jmsg)
	ELSE
		DISPLAY msg
	END IF
	IF m_debugfile THEN
		IF m_logName IS NULL OR m_logName.getLength() < 2 THEN
			LET m_logName =
					YEAR(TODAY) || (MONTH(TODAY) USING "&&") || (DAY(TODAY) USING "&&")
							|| l_time[1, 2] || l_time[4, 5]
		END IF
		IF m_debugOut IS NULL THEN
			LET m_debugOut = base.channel.create()
			IF m_path IS NULL THEN
				LET m_path = "debug" || os.path.separator()
			END IF
		END IF
		TRY
			CALL m_debugOut.openFile(m_path || m_logName || ".log", "a")
		CATCH
			LET msg = "Failed to open " || m_path || m_logName || ".log!!"
			DISPLAY msg
			CALL System.err.println(msg)
			RETURN
		END TRY
		CALL m_debugOut.writeLine(msg)
		CALL m_debugOut.close()
	END IF
--	MESSAGE msg
END FUNCTION
