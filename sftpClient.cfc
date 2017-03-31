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
	Name         : sftpClient.cfc
	Author(s)    : Daniel Budde
	Created      : May 16, 2015
	Requirements : ColdFusion 10+
*/
component displayname="sftpClient" accessors="true" output="false" 
{
	/**********************************/
	/** Properties                   **/
	/**********************************/
	property name="channel";
	property name="currentDirectory" type="string" setter="false" hint="The current working directory on the host." ;
	property name="factory";
	property name="fingerPrint" type="string" hint="The fingerprint to use to identify the Host's key as valid.";
	property name="host" type="string" setter="false" hint="The host to connect to." ;
	property name="hostKey" type="struct" getter="false" setter="false" hint="The host key of the currently set host.";
	property name="logger";
	property name="loggerProxy";
	property name="password" type="string" hint="The password to use when connecting to the host";
	property name="port" type="numeric" hint="The port to use when connecting to the SFTP server. (Default: 22)";
	property name="proxyHost" type="string";
	property name="proxyPassword" type="string";
	property name="proxyPort" type="string";
	property name="proxyUsername" type="string";
	property name="sessionConfig" type="struct";
	property name="sftpSession";
	property name="timeout" type="numeric";
	property name="username" type="string" hint="The username to use when connecting to the host.";




	/**********************************/
	/** Public Methods               **/
	/**********************************/

	/**
	* @key Base64 encoded host key string.
	* @host The host the key should be associated with. Defaults to connection host if not supplied.
	*/
	public void function addHostKey(required string key, string host) hint="Adds a host key to the known hosts."
	{
		local.host = getHost();

		if (structKeyExists(arguments, "host") && len(arguments.host))
		{
			local.host = arguments.host;
		}

		local.hostKey = createObject("java", "com.jcraft.jsch.HostKey").init(local.host, 0, toBinary(arguments.key));

		local.hostKeyRepository = getFactory().getHostKeyRepository();

		local.hostKeyRepository.add(local.hostKey, javacast("null", ""));
	}


	public void function addPrivateKey(required string privateKey, string passPhrase) hint="Adds a private key to authenticate with."
	{
		if (!structKeyExists(arguments, "passPhrase"))
		{
			getFactory().addIdentity(arguments.privateKey);
		}
		else
		{
			getFactory().addIdentity(arguments.privateKey, arguments.passPhrase);
		}
	}


	public void function cd(required string directory) hint="Changes the current directory. Alias for 'changeDirectory'."
	{
		changeDirectory(arguments.directory);
	}


	public void function changeDirectory(required string directory) hint="Changes the current directory."
	{
		requireConnection();


		// Determine directory to use.
		local.directory = translateRemotePath(arguments.directory);


		// Attempt switching directories.
		try
		{
			getChannel().cd(local.directory);
		}
		catch (any exception)
		{
			if (findNoCase("no such file", exception.message))
			{
				throw(message = "The directory (" & local.directory & ") does not exist.");
			}
			else
			{
				rethrow;
			}
		}


		// Record new current directory.
		setCurrentDirectory(local.directory);
	}


	public void function clearLogs() hint="Clears the logs array."
	{
		getLogger().clearLogs();
	}


	public void function connect() hint="Opens a connection to the server using the provided credentials."
	{
		if (isReadyToConnect())
		{
			// Make sure we have a session to work with.
			if (isNull(getSFTPSession()))
			{
				loadSession();
			}


			// See if we can add host to 'knownHosts' based on fingerprint.
			checkKnownHosts();


			getSFTPSession().connect();
			setCurrentDirectory("/");

			if (isNull(getChannel()))
			{
				setChannel(getSFTPSession().openChannel("sftp"));
			}

			getChannel().connect();
		}
	}


	public void function createDirectory(required string directory) hint="Creates a remote directory."
	{
		requireConnection();


		// Determine directory to use.
		local.directory = translateRemotePath(arguments.directory);

		getChannel().mkdir(local.directory);
	} 


	public void function deleteDirectory(required string directory, required boolean recursive = true) hint="Deletes a remote directory."
	{
		requireConnection();


		// Determine directory to use.
		local.directory = translateRemotePath(arguments.directory);


		if (arguments.recursive)
		{
			local.files = getDirectoryList(local.directory);

			for (local.file in local.files)
			{
				if (local.file.type == "File")
				{
					deleteFile(local.directory & local.file.name);
				}
				else
				{
					deleteDirectory(local.directory & local.file.name & "/", true);
				}
			}
		}


		getChannel().rmdir(local.directory);
	} 


	public void function deleteFile(required string filePath) hint="Deletes a remote file." 
	{
		requireConnection();

		getChannel().rmdir(arguments.filePath);
	}


	public void function disconnect() hint="Closes the connection to the server."
	{
		if (!isNull(getChannel()))
		{
			getChannel().disconnect();
		}

		if (!isNull(getSFTPSession()))
		{
			getSFTPSession().disconnect();
		}

		setCurrentDirectory("");

		setChannel(javacast("null", ""));
		setSFTPSession(javacast("null", ""));
	}


	/**
	* @source The file path to the source file on the sftp host.
	* @destination The path to the folder on the local system of where to download the file.
	*/
	public void function downloadFile(required string source, required string destination) hint="Downloads a file to the destination directory."
	{
		requireConnection();

		// Determine file location on server.
		local.source = translateRemotePath(arguments.source, true);

		getChannel().put(local.source, arguments.destination);
	}


	/**
	* @keyType RSA or DSA.
	* @keySize The size of the generated key.
	* @destination The destination folder.
	* @name The name of the file without extension.
	* @passphrase The passphrase used to secure the file.
	* @comment Comment to place in the public key file.
	*/
	public void function generateKeyPair(	required string keyType = "rsa", 
											required numeric keySize = 2048, 
											required string destination, 
											required string name, 
											required string passPhrase = "",
											required string comment = "") 
	hint="Generates a set of key pair files. Files named using the 'name' argument with extensions '.priv' and '.pub' to represent private and public keys respectively." 
	{
		if (directoryExists(arguments.destination))
		{
			arguments.destination = formatPath(arguments.destination);

			local.keyPair = createObject("java", "com.jcraft.jsch.KeyPair");

			if (arguments.keyType == "dsa")
			{
				local.keyType = local.keyPair.DSA;
			}
			else
			{
				local.keyType = local.keyPair.RSA;
			}

			local.keyPair = local.keyPair.genKeyPair(getFactory(), local.keyType, arguments.keySize);

			if (len(arguments.passPhrase))
			{
				local.keyPair.setPassphrase(arguments.passPhrase);
			}


			local.keyPair.writePrivateKey(arguments.destination & arguments.name & ".priv");
			local.keyPair.writePublicKey(arguments.destination & arguments.name & ".pub", arguments.comment);
		}
	}


	/**
	* @source The file path to the source file on the sftp host.
	* @destination The path to the folder on the local system of where to download the file.
	*/
	public void function get(required string source, required string destination) hint="Downloads a file to the destination directory. Alias for 'downloadFile'."
	{
		downloadFile(arguments.source, arguments.destination);
	}


	public struct function getConnectionInfo() hint="Returns information on the current connection."
	{
		local.info =
		{
			"host": getHost(),
			"isConnected": isConnected(),
			"port": getPort(),
			"timeout": getTimeout(),
			"username": getUsername()
		};


		// Grab proxy information.
		if (len(getProxyHost()))
		{
			local.info["proxy"] = {};
			local.info.proxy["host"] = getProxyHost();

			if (len(getProxyPort()))
			{
				local.info.proxy["port"] = getProxyPort();
			}

			if (len(getProxyUsername()))
			{
				local.info.proxy["username"] = getProxyUsername();
			}
		}


		// Connected, so grab current directory information.
		if (isConnected())
		{
			local.info["currentDirectory"] = getCurrentDirectory();

			local.info["currentDirectoryList"] = getDirectoryList();
		}


		return local.info;
	}


	/**
	* @directory 
	* @host The host the key should be associated with. Defaults to connection host if not supplied.
	*/
	public any function getDirectoryList(string directory, string dataType = "query") hint="Returns a list of the files and folders in the current directory."
	{
		requireConnection();


		// Determine directory to use.
		local.directory = getCurrentDirectory();

		if (structKeyExists(arguments, "directory") && len(arguments.directory))
		{
			local.directory = translateRemotePath(arguments.directory);
		}


		try
		{
			local.files = convertEntryArray(getChannel().ls(local.directory));
		}
		catch (any exception)
		{
			if (findNoCase("no such file", exception.message))
			{
				throw(message = "The directory (" & local.directory & ") does not exist.");
			}
			else
			{
				rethrow;
			}
		}


		if (arguments.dataType == "query")
		{
			local.query = queryNew("name,directory,dateLastModified,link,size,type", "varchar,varchar,date,bit,integer,varchar");

			for (local.file in local.files)
			{
				local.type = "File";

				if (local.file.isDirectory)
				{
					local.type = "Dir";
				}

				queryAddRow(local.query);
				querySetCell(local.query, "name", local.file.fileName);
				querySetCell(local.query, "directory", local.directory);
				querySetCell(local.query, "dateLastModified", local.file.modified);
				querySetCell(local.query, "link", local.file.isLink);
				querySetCell(local.query, "size", local.file.size);
				querySetCell(local.query, "type", local.type);
			}

			local.files = local.query;
		}


		return local.files;
	}


	public any function getHostKey(required boolean ignoreKnownHosts = false) hint="Gets the host key information."
	{
		local.hostKey = {};

		if (isReadyToConnect() && structIsEmpty(variables.hostKey))
		{
			local.knownHostsBefore = getKnownHosts();
			local.sftpSession = createSession();

			if (arguments.ignoreKnownHosts)
			{
				local.sftpSession.setConfig("StrictHostKeyChecking", "no");
			}

			local.sftpSession.connect();

			local.hostKey = local.sftpSession.getHostKey();
			
			local.sftpSession.disconnect();

			local.hostKey = convertHostKey(local.hostKey);

			setHostKey(local.hostKey);


			// Remove the host key if it was retained.
			if (arguments.ignoreKnownHosts)
			{
				local.knownHostsAfter = getKnownHosts();

				if (local.knownHostsAfter.len() > local.knownHostsBefore.len())
				{
					getFactory().getHostKeyRepository().remove(local.hostKey.host, local.hostKey.type, toBinary(local.hostKey.key));
				}
			}
		}
		else if (!structIsEmpty(variables.hostKey))
		{
			local.hostKey = variables.hostKey;
		}

		return local.hostKey;
	}


	public array function getKnownHosts() hint="Returns all stored host keys."
	{
		local.hostKeyRepository = getFactory().getHostKeyRepository();
		local.hostKeys = local.hostKeyRepository.getHostKey();

		if (isNull(local.hostKeys))
		{
			return [];
		}

		return convertHostKey(local.hostKeys);
	}


	public array function getLogs() hint="Retrieves the recorded logs from the logger."
	{
		return getLogger().getLogs();
	}


	public any function init() hint="Constructor."
	{
		setSessionConfig({});
		setPort(22);
		setProxyPort(80);
		setTimeout(10);
		setCurrentDirectory("");
		setFingerPrint("");
		setFactory(createObject("java", "com.jcraft.jsch.JSch"));
		setHostKey({});


		local.logger = new sftpClientLogger();
		local.loggerProxy = createDynamicProxy(local.logger, ["com.jcraft.jsch.Logger"]);

		setLogger(local.logger);
		setLoggerProxy(local.loggerProxy);


		getFactory().setLogger(getLoggerProxy());


		if (!structIsEmpty(arguments))
		{
			for (local.key in arguments)
			{
				if (structKeyExists(this, "set" & local.key))
				{
					invoke(this, "set" & local.key, {"1": arguments[local.key]});
				}
			}
		}
		
		return this;
	}


	public boolean function isConnected() hint="Determines if the sftp client is connected."
	{
		if (!isNull(getSFTPSession()) && !isNull(getChannel()) && getSFTPSession().isConnected() && getChannel().isConnected())
		{
			return true;
		}

		return false;
	} 


	public boolean function isReadyToConnect() hint="Determines if all necessary credentials to connect to a SFTP server have been set."
	{
		if (
				!isNull(getHost()) && len(getHost()) && 
				!isNull(getUsername()) && len(getUsername()) && 
				(
					arrayLen(getFactory().getIdentityNames()) ||
					(!isNull(getPassword()) && len(getPassword()))
				)
			)
		{
			return true;
		}

		return false;
	}


	public any function ls(string directory, string dataType) hint="Returns a list of the files and folders in the current directory. Alias for 'getDirectoryList'."
	{
		return getDirectoryList(argumentCollection = arguments);
	}


	public void function mkdir(required string directory) hint="Creates a remote directory. Alias for 'createDirectory'."
	{
		createDirectory(arguments.directory);
	} 


	public void function put(required string source, string destination) hint="Uploads a file to the destination directory. Alias for 'uploadFile'."
	{
		uploadFile(arguments.source, arguments.destination);
	}


	public void function rename(required string source, required string destination) hint="Renames a file or folder on the remote server."
	{
		requireConnection();

		local.source = translateRemotePath(arguments.source);
		local.destination = translateRemotePath(arguments.destination);

		getChannel().rename(local.source, local.destination);
	}


	public void function rm(required string filePath) hint="Deletes a remote file. Alias for 'deleteFile'." 
	{
		deleteFile(arguments.filePath);
	}


	public void function rmdir(required string directory, required boolean recursive) hint="Deletes a remote directory. Alias for 'deleteDirectory'."
	{
		deleteDirectory(arguments.directory, arguments.recursive);
	} 


	public void function setConfigOption(required string name, required string value)
	{
		getSessionConfig()[arguments.name] = arguments.value;
	}


	public void function setHost(required string host)
	{
		variables.host = arguments.host;
		setHostKey({});
	}


	public void function setLogLevel(required string level = "warn") hint="Sets the level as to what to store in the logging object. ()"
	{
		getLogger().setLogLevel(arguments.level);
	}


	public void function setStrictHostKeyChecking(required boolean strict = true)
	{
		if (arguments.strict)
		{
			setConfigOption("StrictHostKeyChecking", "yes");
		}
		else
		{
			setConfigOption("StrictHostKeyChecking", "no");
		}
	}


	/**
	* @source The file path to the source file to upload.
	* @destination The path to the folder on the host where the file should be placed. Defaults to current directory.
	*/
	public void function uploadFile(required string source, string destination) hint="Uploads a file to the destination directory."
	{
		requireConnection();


		// Determine directory to use.
		local.destination = getCurrentDirectory();

		if (structKeyExists(arguments, "destination") && len(arguments.destination))
		{
			local.destination = translateRemotePath(arguments.destination);
		}

		getChannel().put(arguments.source, local.destination);
	}


	/**
	* @logFilePath - Fully expanded path to a log file to write to.
	* @fieldDelimiter - The delimiter to be used between fields. Defaults to a tab.
	* @lineDelimiter - The delimiter to be used between log lines. Defaults to Carriage Return and Line Feed.
	*/
	public void function writeLog(required string logFilePath, string fieldDelimiter = chr(9), string lineDelimiter = chr(13) & chr(10)) 
		hint="Writes the logs to a file.  Creates the directory path and file if it does not exist."
	{
		getLogger().writeLog(argumentCollection = arguments);
	}




	/**********************************/
	/** Private Methods              **/
	/**********************************/
	private void function checkKnownHosts() hint="Checks to see if host can be added to 'knownHosts' based on fingerprint."
	{
		if (len(getFingerPrint()))
		{
			local.hostKey = getHostKey(true);

			// Fingerprints match, add to known hosts.
			if (getFingerPrint() == local.hostKey.fingerPrint)
			{
				addHostKey(local.hostKey.key);
			}
		}
	}


	private any function convertEntry(required any entry) hint="Converts a 'ls' entry." 
	{
		local.attributes = arguments.entry.getAttrs();

		local.entry = 
		{
			// "attributes": local.attributes,
			"filename": arguments.entry.getFilename(),
			"isDirectory": local.attributes.isDir(),
			"isLink": local.attributes.isLink(),
			// "lastAccessed": local.attributes.getATimeString(),
			// "longname": arguments.entry.getLongname(),
			"modified": convertEpochTime(local.attributes.getMTime()),
			"permissions": local.attributes.getPermissionsString(),
			"size": local.attributes.getSize()
		};

		// Directory size is not accurate.
		if (local.entry.isDirectory)
		{
			local.entry.size = 0;
		}

		return local.entry;
	}


	private any function convertHostKey(required any hostKey) hint="Converts a host key to a structure."
	{
		if (isArray(arguments.hostKey))
		{
			local.hostKeys = [];

			for (local.hostKey in arguments.hostKey)
			{
				local.hostKeys.append(convertHostKey(local.hostKey));
			}

			local.hostKey = local.hostKeys;
		}
		else
		{
			local.hostKey =
			{
				"fingerPrint": arguments.hostKey.getFingerPrint(getFactory()),
				"host": arguments.hostKey.getHost(),
				//"hostKey": arguments.hostKey,
				"key": arguments.hostKey.getKey(),
				"type": arguments.hostKey.getType()
			};
		}

		return local.hostKey;
	}


	private any function convertEntryArray(required any entryArray) hint="Converts a 'ls' entry array." 
	{
		local.entryArray = [];

		for (local.entry in arguments.entryArray)
		{
			local.convertedEntry = convertEntry(local.entry);

			if (!listFind(".,..", local.convertedEntry.filename))
			{
				local.entryArray.append(local.convertedEntry);
			}
		}

		return local.entryArray;
	}


	private date function convertEpochTime(required numeric dateSeconds) hint="Converts numeric epoch date to datetime." 
	{
		local.startDate = createODBCDateTime("1970-01-01 00:00:00.000");

		return dateConvert("utc2local", dateAdd("s", arguments.dateSeconds, local.startDate));
	}


	private any function createSession() hint="Creates the SFTP session."
	{
		local.config = getSessionConfig();
		local.factory = getFactory();

		local.sftpSession = local.factory.getSession(getUsername(), getHost(), getPort());

		if (!isNull(getPassword()) && len(getPassword()))
		{
			local.sftpSession.setPassword(getPassword());
		}

		if (!structIsEmpty(local.config))
		{
			for (local.key in local.config)
			{
				local.sftpSession.setConfig(local.key, local.config[local.key]);
			}
		}

		if (!isNull(getProxyHost()) && len(getProxyHost()))
		{
			local.proxy = createObject("java", "com.jcraft.jsch.ProxyHTTP").init(getProxyHost(), getProxyPort());

			if (!isNull(getProxyUsername()) && !isNull(getProxyPassword()))
			{
				local.proxy.setUserPasswd(getProxyUsername(), getProxyPassword());
			}

			local.sftpSession.setProxy(local.proxy);
		}

		return local.sftpSession;
	}


	private string function formatPath(required string path) hint="Makes sure there is a system delimiter on the end."
	{
		local.systemDelimiter = "/";

		if (find("\", arguments.path))
		{
			local.systemDelimiter = "\";
		}

		if (right(arguments.path, 1) != local.systemDelimiter)
		{
			arguments.path &= local.systemDelimiter;
		}

		return arguments.path;
	} 


	private void function loadSession() hint="Loads the SFTP session."
	{
		setSFTPSession(createSession());
	}


	private void function requireConnection() hint="Throws an error if the sftp client is not connected to a server."
	{
		if (!isConnected())
		{
			local.callStack = callStackGet();
			local.function = local.callStack[2]["function"];

			throw(message = "The sftp client must be connected to a server before calling (" & local.function & ").");
		}
	} 


	private void function setCurrentDirectory(required string directory)
	{
		if (right(arguments.directory, 1) != "/")
		{
			arguments.directory &= "/";
		}

		variables.currentDirectory = arguments.directory;
	}


	private void function setHostKey(required struct hostKey) hint="Set the host key."
	{
		variables.hostKey = arguments.hostKey;
	}


	private string function translateRemotePath(required string directory, required boolean isFile = false) 
			hint="Deterines if the directory is relative and formats it using current directory." 
	{
		local.directory = arguments.directory;

		if (left(local.directory, 1) != "/")
		{
			local.directory = getCurrentDirectory() & local.directory;
		}


		if (right(local.directory, 1) != "/" && !arguments.isFile)
		{
			local.directory &= "/";
		}


		return local.directory;
	}


}
