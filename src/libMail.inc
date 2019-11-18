
#+ A library for interfacing with IMAPI/SMTP mail servers - only tested 
#+ so far with googlemail. -- loosly based on java mail api demos.
#+ Required Genero 2.2x or above
#+ Java and mail.jar
#+
#+ By Neil J.Martin ( neilm@4js.com ) 

CONSTANT ATTACH_OUT = "attach_out"

TYPE t_mail RECORD
		flags STRING,
		flg_junk STRING,
		flg_answered STRING,
		flg_attach STRING,
		flg_fjs STRING,
		content_type VARCHAR(60),
		subj STRING,
		from_whom STRING,
		when STRING,
		when2 DATETIME YEAR TO SECOND,
		to_whom STRING,
		reply_to STRING,
		head_key INTEGER
	END RECORD
TYPE t_colr_mail RECORD
			col1 STRING,
			col2 STRING,
			col3 STRING,
			col4 STRING,
			col5 STRING,
			col6 STRING,
			col7 STRING,
			col8 STRING
		END RECORD

TYPE t_recp RECORD
			mode STRING,
			addr STRING
	END RECORD

TYPE t_mbox RECORD
		id SMALLINT,
		pid SMALLINT,
		img VARCHAR(20),
		name VARCHAR(50),
		fullname VARCHAR(50)
	END RECORD

-- Email Header Record - head_key INTEGER/SERIAL
&define D_EMAILHEADER \
			account VARCHAR(50), \
			foldername VARCHAR(40), \
			message_no INTEGER, \
			call_no INTEGER, \
			h_from VARCHAR(60), \
			h_to VARCHAR(60), \
			h_reply_to VARCHAR(60), \
			senddate VARCHAR(40), \
			senddatetime DATETIME YEAR TO SECOND, \
			subject VARCHAR(200), \
			content_type VARCHAR(60), \
			flags VARCHAR(100), \
			flg_attach SMALLINT, \
			flg_answered SMALLINT, \
			flg_junk SMALLINT

-- Mail body record
&define D_EMAILBODYPART \
			head_key INTEGER, \
			mime_type CHAR(50), \
			filename CHAR(50), \
			localname CHAR(20), \
			part_no SMALLINT, \
			mbody TEXT
