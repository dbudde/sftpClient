/**
	MIT License

	Copyright (c) 2015 Daniel Budde

	Permission is hereby granted, free of charge, to any person obtaining a copy
	of this software and associated documentation files (the "Software"), to deal
	in the Software without restriction, including without limitation the rights
	to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
	copies of the Software, and to permit persons to whom the Software is
	furnished to do so, subject to the following conditions:

	The above copyright notice and this permission notice shall be included in all
	copies or substantial portions of the Software.

	THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
	IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
	FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
	AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
	LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
	OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
	SOFTWARE.

*
	Name         : sftpClientLogger.cfc
	Author(s)    : Daniel Budde
	Created      : March 20, 2017
	Requirements : ColdFusion 10+
*/
component displayname="sftpClientLogger" accessors="true" output="false" 
{
	/**********************************/
	/** Properties                   **/
	/**********************************/
	property name="level" type="numeric" hint="The logging level to record.";
	property name="logs" type="array" hint="An array of the recorded logs.";




	/**********************************/
	/** Public Methods               **/
	/**********************************/
	public void function clearLogs() hint="Clears the logs array."
	{
		setLogs([]);
	}


	public void function init() hint="Constructor."
	{
		setLogLevel("WARN");
		setLogs([]);
	}


	/**
	* @level - The log level to check and see if it is enabled. (FATAL, ERROR, WARN, INFO, DEBUG)
	*/
	public boolean function isEnabled(required numeric level) hint="Tests whether the logging level is enabled."
	{
		if (getLevel() <= arguments.level)
		{
			return true;
		}

		return false;
	}


	/**
	* @level - The log level being reported with the message to be logged. (FATAL, ERROR, WARN, INFO, DEBUG)
	* @message - The message to be logged.
	*/
	public void function log(required numeric level, required string message) hint="Records a log message if the level is to be recorded."
	{
		if (getLevel() <= arguments.level)
		{
			getLogs().append({"level": arguments.level, "message": arguments.message, "occurred": now()});
		}
	}


	/**
	* @level - The log level to start recording messages. (FATAL, ERROR, WARN, INFO, DEBUG)
	*/
	public void function setLogLevel(required string level) hint="Sets the level of logging to record."
	{
		local.level = ucase(arguments.level);

		if (!listFind("FATAL,ERROR,WARN,INFO,DEBUG", local.level))
		{
			local.level = "WARN";
		}

		local.loggerInterface = createObject("java", "com.jcraft.jsch.Logger");

		setLevel(evaluate("local.loggerInterface." & local.level));
	}


	/**
	* @logFilePath - Fully expanded path to a log file to write to.
	* @fieldDelimiter - The delimiter to be used between fields. Defaults to a tab.
	* @lineDelimiter - The delimiter to be used between log lines. Defaults to Carriage Return and Line Feed.
	*/
	public void function writeLog(required string logFilePath, string fieldDelimiter = chr(9), string lineDelimiter = chr(13) & chr(10)) 
		hint="Writes the logs to a file.  Creates the directory path and file if it does not exist."
	{
		local.directory = getDirectoryFromPath(arguments.logFilePath);

		if (!directoryExists(local.directory))
		{
			directoryCreate(local.directory);
		}


		if (fileExists(arguments.logFilePath))
		{
			local.logFile = fileOpen(arguments.logFilePath, "append");
		}
		else
		{
			local.logFile = fileOpen(arguments.logFilePath, "write");
		}


		for (local.log in getLogs())
		{
			local.line = "[" & dateTimeFormat(local.log.occurred, "yyyy-mm-dd HH:nn:ss l") & "]" & arguments.fieldDelimiter;
			local.line &= "[" & local.log.level & "]" & arguments.fieldDelimiter;
			local.line &= local.log.message & arguments.lineDelimiter;

			fileWrite(local.logFile, local.line);
		}


		fileClose(local.logFile);
	}





	/**********************************/
	/** Private Methods              **/
	/**********************************/
	/*
	private void function priv() hint=""
	{
		
	}
	*/


}