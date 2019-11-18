
#+ $Id: libMailJava.inc 624 2010-04-28 17:01:26Z  $
#+
#+ A library for interfacing with IMAPI/SMTP mail servers - only tested 
#+ so far with googlemail. -- loosly based on java mail api demos.
#+ Required Genero 2.2x or above
#+ Java and mail.jar
#+
#+ By Neil J.Martin ( neilm@4js.com ) 

-- JAVA bits {{{
--IMPORT JAVA java.util.*
--IMPORT JAVA java.io.*
--IMPORT JAVA javax.mail.*
--IMPORT JAVA javax.mail.event.*
--IMPORT JAVA javax.mail.internet.*

IMPORT JAVA java.lang.Object
IMPORT JAVA java.lang.System
IMPORT JAVA java.lang.String
IMPORT JAVA java.lang.StringBuffer
IMPORT JAVA java.lang.Exception
IMPORT JAVA java.lang.Throwable
IMPORT JAVA java.text.DateFormat
IMPORT JAVA java.io.InputStream
IMPORT JAVA java.io.File
IMPORT JAVA java.util.Properties
IMPORT JAVA java.util.Date
IMPORT JAVA javax.mail.Part
IMPORT JAVA javax.mail.Flags
IMPORT JAVA javax.mail.Flags.Flag
IMPORT JAVA javax.mail.Message
IMPORT JAVA javax.mail.Message.RecipientType
IMPORT JAVA javax.mail.Multipart
IMPORT JAVA javax.mail.Address
IMPORT JAVA javax.mail.internet.InternetAddress
IMPORT JAVA javax.mail.internet.MimeBodyPart
IMPORT JAVA javax.mail.internet.MimeMultipart
IMPORT JAVA javax.mail.internet.ContentType
IMPORT JAVA javax.mail.internet.MimeMessage
IMPORT JAVA javax.mail.Session
IMPORT JAVA javax.mail.Authenticator
IMPORT JAVA javax.mail.Store
IMPORT JAVA javax.mail.Folder
IMPORT JAVA javax.mail.FetchProfile
IMPORT JAVA javax.mail.FetchProfile.Item
IMPORT JAVA javax.mail.internet.MimeMessage
IMPORT JAVA javax.mail.Transport
IMPORT JAVA javax.mail.SendFailedException
IMPORT JAVA javax.mail.MessagingException
--IMPORT JAVA javax.activation.*
--}}}

