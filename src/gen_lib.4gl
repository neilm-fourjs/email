
#+ CaseLog Library Code.
#+ $Id: gen_lib.4gl 1332 2013-01-16 09:24:09Z  $
#+
#+ This module initially written by: Neil J.Martin ( neilm@4js.com ) 
#+
#+ Code should be self-documenting: 
#+ -Comments should be avoided whenever possible. 
#+ -Comments duplicate work when both writing and reading code. 
#+ -If you need to comment something to make it understandable it should probably be rewritten.
#+
IMPORT os
&ifndef NOWS
IMPORT com
IMPORT xml
&endif

&define GL_DBGMSG( lev, msg ) \
	CALL logDebug( __LINE__, __FILE__, lev, NVL(msg,"NULL!")) \

----------------------------------------------------------------------------------

#+ Simple xml cfg code - open file and return root node.
#+
#+ @param file file name
#+ @return Null or node.
FUNCTION cfgRead(file) --{{{
	DEFINE file STRING
	DEFINE cfg om.DomDocument
	TRY
		LET cfg = om.DomDocument.createFromXmlFile( file )
	CATCH
		CALL fgl_winMessage("Error","Failed to read config:"||file,"exclamation")
		RETURN NULL
	END TRY
	IF cfg IS NULL THEN
		CALL fgl_winMessage("Error","Failed to read config:"||file,"exclamation")
	END IF
	RETURN cfg.getDocumentElement()
END FUNCTION --}}}
--------------------------------------------------------------------------------
#+ Simple xml cfg code - return the value for a node of type 'what'
#+
#+ @param what Tag name
#+ @param n node returned by cfgRead
#+ @return NULL or value
FUNCTION cfgFetch(what, n) --{{{
	DEFINE what STRING
	DEFINE n om.DomNode
	DEFINE nl om.NodeList

	LET nl = n.selectByTagName(what)
	IF nl.getLength() > 0 THEN
		LET n = nl.item(1)
		RETURN n.getAttribute("value")
	END IF
	RETURN NULL
END FUNCTION --}}}
