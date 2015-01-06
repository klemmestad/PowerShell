Option Explicit
' -----------------------------------------------------------------------------
' Processor Sensor Information - Alert When Not OK
' -----------------------------------------------------------------------------
' Parameters:
' script.vbs --username "Username" -password "Password" -host "111.111.111.111"
' -----------------------------------------------------------------------------
' Version Information
' -----------------------------------------------------------------------------
' $LastChangedDate: 2013-03-15 14:19:20 +0000 (Fri, 15 Mar 2013) $
' $Rev: 38413 $
' -----------------------------------------------------------------------------

	Const PASSED_CHECK							= 0
	Const ERROR_MISSING_ARGUMENTS				= 1
	Const ERROR_CONNECTION_FAIL_CREDENTIALS		= 1001
	Const ERROR_CONNECTION_FAIL_WSMAN_HOST		= 1002
	Const ERROR_CONNECTION_FAIL_WSMAN_ESX		= 1003
	Const ERROR_CONNECTION_FAIL_WSMAN_UNKNOWN	= 1004
	Const FAILED_CHECK							= 2003
	
	Const CONNECTION_FAIL_WSMAN_STATUS			= -1
	Const CONNECTION_FAIL_CREDENTIALS_STATUS	= -2
	Const HEALTHSTATE_UNKNOWN					= "0"
	Const HEALTHSTATE_OK						= "5"
	Const EXPECTED_ARGUMENTS					= 6
	
	Private Host
	Private Username
	Private Password
	
	Private isConnected		'True/False
	
	Private OMCSchema
	Private DMTFSchema
	Private VMWareSchema

	Private oWSMan
	Private oOptions
	Private oSession
	
	Private sXmlDocContent
	Private fSuccess
	Private nFailing
	Private nPassing
	Private nUnknown
	
	Private forceFailMode
	
	Public Function Class_Initialize()
		fSuccess = 1
		nFailing = 0
		nPassing = 0
		nUnknown = 0
		OMCSchema = "http://schema.omc-project.org/wbem/wscim/1/cim-schema/2/"
		DMTFSchema = "http://schemas.dmtf.org/wbem/wscim/1/cim-schema/2/"
		VMWareSchema = "http://schemas.vmware.com/wbem/wscim/1/cim-schema/2/"
	End Function
	
	Public Function setCredentials(strHost, strUsername, strPassword)
		Host = strHost
		Username = strUsername
		Password = strPassword
	End Function
	
	Public Function Connect(fSkipCA, fSkipCN)
		Set oWSMan = CreateObject("Wsman.Automation")
		Set oOptions = oWSMan.CreateConnectionOptions
		
		oOptions.userName = Username
		oOptions.Password = Password
		
		Dim ConnectionFlags : ConnectionFlags = oWSMan.SessionFlagUseBasic
		ConnectionFlags = ConnectionFlags Or oWSMan.SessionFlagCredUserNamePassword
		ConnectionFlags = ConnectionFlags Or oWSMan.SessionFlagUTF8
		
		On Error Resume Next
		ConnectionFlags =  ConnectionFlags Or oWSMan.SessionFlagSkipRevocationCheck 
		If fSkipCA = True Then 
			ConnectionFlags = ConnectionFlags Or oWSMan.SessionFlagSkipCACheck
		End If
		If fSkipCN = True Then 
			ConnectionFlags = ConnectionFlags Or oWSMan.SessionFlagSkipCNCheck
		End If
		On Error Goto 0
		
		Set oSession = oWSMan.CreateSession("https://" & Host & "/wsman",ConnectionFlags,oOptions)
		
		If oSession is Nothing Then
		  Connect = CONNECTION_FAIL_WSMAN_STATUS 'WSMan is either not installed or credentials failed.
		End If
		
	End Function
	
	
	'{GFI-MIXINS}
	
	Private Function updateSummaryHealthCounts( healthState )
		If HealthState = HEALTHSTATE_OK Then
			nPassing = nPassing + 1
		ElseIf HealthState = HEALTHSTATE_UNKNOWN Then
			nUnknown = nUnknown + 1
		Else
			fSuccess = 0
			nFailing = nFailing + 1
		End If
	End Function

	Public Function getProcessorCheckInformation
		Dim Caption
		Dim HealthState
		Dim EnabledDefault
		Dim EnabledState
		Dim CurrentClockSpeed
		Dim MaxClockSpeed
		Dim Level
		Dim NumberOfBlocks
		Dim ReadPolicy
		Dim WritePolicy
		Dim ModelName
		Dim ErrorMethodology
		Dim NumberOfEnabledCores
		Dim xmlDom

		Dim strBase : strBase = getBaseURL("OMC_Processor")
		Dim strQueryResource : strQueryResource = strBase & "OMC_Processor"
		Dim oQueryResponse : Set oQueryResponse = oSession.Enumerate(strQueryResource)
		While Not oQueryResponse.AtEndOfStream
			Set xmlDom = LoadDom( oQueryResponse.ReadItem )

			Caption = ParseXML(xmlDom, "/n1:OMC_Processor/n1:Caption")
			ModelName = ParseXML(xmlDom, "/n1:OMC_Processor/n1:ModelName")
			NumberOfEnabledCores = ParseXML(xmlDom, "/n1:OMC_Processor/n1:NumberOfEnabledCores")
			CurrentClockSpeed = ParseXML(xmlDom, "/n1:OMC_Processor/n1:CurrentClockSpeed") & " MHz"
			MaxClockSpeed = ParseXML(xmlDom, "/n1:OMC_Processor/n1:MaxClockSpeed") & " MHz"
			EnabledDefault = ParseXML(xmlDom, "/n1:OMC_Processor/n1:EnabledDefault")
			EnabledState = ParseXML(xmlDom, "/n1:OMC_Processor/n1:EnabledState")
			HealthState = Replace(ParseXML(xmlDom, "/n1:OMC_Processor/n1:HealthState"), "NULL", "0")

			updateSummaryHealthCounts HealthState
			
			sXmlDocContent = sXmlDocContent & "<sensor type='OMC_Processor' caption='" & Caption & "' model_name='" & ModelName & "' number_of_enabled_cores='" & NumberOfEnabledCores & "' current_clock_speed='" & CurrentClockSpeed & "' max_clock_speed='" & MaxClockSpeed & "' enabled_default='" & EnabledDefault & "' enabled_state='" & EnabledState & "' health_state='" & HealthState & "'/>"
		WEnd
		
		strBase = getBaseURL("OMC_ProcessorCore")
		strQueryResource = strBase & "OMC_ProcessorCore"
		Set oQueryResponse = oSession.Enumerate(strQueryResource)
		While Not oQueryResponse.AtEndOfStream
			Set xmlDom = LoadDom( oQueryResponse.ReadItem )
			Caption = ParseXML(xmlDom, "/n1:OMC_ProcessorCore/n1:Caption")
			HealthState = Replace(ParseXML(xmlDom, "/n1:OMC_ProcessorCore/n1:HealthState"), "NULL", "0")
			EnabledDefault = ParseXML(xmlDom, "/n1:OMC_ProcessorCore/n1:EnabledDefault")
			EnabledState = ParseXML(xmlDom, "/n1:OMC_ProcessorCore/n1:EnabledState")
			
			updateSummaryHealthCounts HealthState
			
			sXmlDocContent = sXmlDocContent & "<sensor type='OMC_ProcessorCore' caption='" & Caption & "' enabled_default='" & EnabledDefault & "' enabled_state='" & EnabledState & "' health_state='" & HealthState & "'/>"
		WEnd
		
		strBase = getBaseURL("OMC_HardwareThread")
		strQueryResource = strBase & "OMC_HardwareThread"
		Set oQueryResponse = oSession.Enumerate(strQueryResource)
		While Not oQueryResponse.AtEndOfStream
			Set xmlDom = LoadDom( oQueryResponse.ReadItem )
			Caption = ParseXML(xmlDom, "/n1:OMC_HardwareThread/n1:Caption")
			HealthState = Replace(ParseXML(xmlDom, "/n1:OMC_HardwareThread/n1:HealthState"), "NULL", "0")
			
			updateSummaryHealthCounts HealthState
			
			sXmlDocContent = sXmlDocContent & "<sensor type='OMC_HardwareThread' caption='" & Caption & "' health_state='" & HealthState & "'/>"
		WEnd
		
		strBase = getBaseURL("OMC_CacheMemory")
		strQueryResource = strBase & "OMC_CacheMemory"
		Set oQueryResponse = oSession.Enumerate(strQueryResource)
		While Not oQueryResponse.AtEndOfStream
			Set xmlDom = LoadDom( oQueryResponse.ReadItem )
			Caption = ParseXML(xmlDom, "/n1:OMC_CacheMemory/n1:Caption")
			Level = ParseXML(xmlDom, "/n1:OMC_CacheMemory/n1:Level")
			NumberOfBlocks = ParseXML(xmlDom, "/n1:OMC_CacheMemory/n1:NumberOfBlocks")
			ReadPolicy = ParseXML(xmlDom, "/n1:OMC_CacheMemory/n1:ReadPolicy")
			WritePolicy = ParseXML(xmlDom, "/n1:OMC_CacheMemory/n1:WritePolicy")
			ErrorMethodology = ParseXML(xmlDom, "/n1:OMC_CacheMemory/n1:ErrorMethodology")
			EnabledDefault = ParseXML(xmlDom, "/n1:OMC_CacheMemory/n1:EnabledDefault")
			EnabledState = ParseXML(xmlDom, "/n1:OMC_CacheMemory/n1:EnabledState")
			
			sXmlDocContent = sXmlDocContent & "<sensor type='OMC_CacheMemory' caption='" & Caption & "' level='" & Level & "' number_of_blocks='" & NumberOfBlocks & "' read_policy='" & ReadPolicy & "' write_policy='" & WritePolicy  & "' error_methodology='" & ErrorMethodology &  "' enabled_default='" & EnabledDefault & "' enabled_state='" & EnabledState & "'/>"
		WEnd
		
	End Function
	
	Public Function getBaseURL(strCIMClass)
		If inStr(strCIMClass, "CIM_") <> 0 Then
			GetBaseURL = DMTFSchema
		ElseIf inStr(strCIMClass, "OMC_") <> 0 Then
			GetBaseURL = OMCSchema
		ElseIf inStr(strCIMClass, "VMware_") <> 0 Then
			GetBaseURL = VMWareSchema
		Else
		  GetBaseURL = -1
		End If
	End Function
	
	Public Function LoadDom( ByRef Response )
		Dim xmlData : Set xmlData = CreateObject("MSXml2.DOMDocument.3.0")	
		xmlData.LoadXml( Response )
		Set LoadDom = xmlData
	End Function

	Public Function ParseXML( ByRef xmlData,NodeName )
		If forceFailMode Then changeHealthValues xmlData
		Dim node : Set node = xmlData.selectSingleNode(NodeName)
		Dim attrib : attrib = node.getAttribute("xsi:nil") & ""
		If attrib = "true" Then
			ParseXML = "NULL"
		Else
			ParseXML = node.text
		End If
	End Function
	
	Public Function checkArguments
		For nArgCount = 0 to Args.Count - 1
			Select Case UCase(Args(nArgCount))
				Case "-FORCEFAIL"
					forceFailMode = True
				Case "-HOST"
					If Args.Count >= ( nArgCount + 1 ) Then
						sHost = Args( nArgCount + 1 )
					End If
				Case "-USERNAME"
					If Args.Count >= ( nArgCount + 1 ) Then
						sUsername = Args( nArgCount + 1 )
					End If
				Case "-PASSWORD"
					If Args.Count >= ( nArgCount + 1 ) Then
						sPassword = Args( nArgCount + 1 )
					End If
			End Select
		Next

		If Args.Count < EXPECTED_ARGUMENTS Then
			WScript.Echo ERROR_MISSING_ARGUMENTS & "|" & "Error: Not Enough Arguments"
			WScript.Quit ERROR_MISSING_ARGUMENTS
		End If
	End Function
	
	Private Function changeHealthValues(ByRef xmlDoc)
		Dim nodes :Set nodes = xmlDoc.documentElement.selectNodes("//n1:HealthState")
		Dim i
		For i = 0 To nodes.Length -1
			nodes(i).Text = 6 
		Next
	End Function
	
	Public Function checkConnectionState
		On Error Resume Next
			oSession.Identify
			'WScript.Echo Err.Description
			'WScript.Echo hex(Err.Number)
			If Err.Number <> 0 Then
				If hex(Err.Number) = "80338126" Then
					WScript.Echo ERROR_CONNECTION_FAIL_WSMAN_HOST & "|" & "Failed to Connect - Host Unreachable"
					WScript.Quit ERROR_CONNECTION_FAIL_WSMAN_HOST
				ElseIf hex(Err.Number) = "80072F8F" Then
					WScript.Echo ERROR_CONNECTION_FAIL_WSMAN_ESX & "|" & "Failed to Connect - Not an ESX Server"
					WScript.Quit ERROR_CONNECTION_FAIL_WSMAN_ESX
				ElseIf hex(Err.Number) = "80070005" Then
					WScript.Echo ERROR_CONNECTION_FAIL_CREDENTIALS & "|" & "Failed to connect - Ensure credentials are valid/have correct permissions"
					WScript.Quit ERROR_CONNECTION_FAIL_CREDENTIALS
				Else 
					WScript.Echo ERROR_CONNECTION_FAIL_WSMAN_UNKNOWN & "|" & "Failed to connect - An unknown error occured. Please ensure this host is a valid ESX server"
					WScript.Quit ERROR_CONNECTION_FAIL_WSMAN_UNKNOWN
				End If
			End If
		On Error Goto 0

		Err.Clear
		
		isConnected = True
	End Function


' -----------------------------------------------------------------------------
' Run the Script
' -----------------------------------------------------------------------------

' Expected Arguments
' -host
' -username
' -password


Dim sHost
Dim sUsername
Dim sPassword

Dim Args
Set Args = WScript.Arguments

Dim nArgCount


Class_Initialize
checkArguments
setCredentials sHost, sUsername, sPassword
Connect True,True
checkConnectionState

' start forming the xml string
sXmlDocContent = "<?xml version='1.0' encoding='UTF-8'?>"
sXmlDocContent = sXmlDocContent & "<dataset>"
' get processor information
sXmlDocContent = sXmlDocContent & "<processorcheck>"
getProcessorCheckInformation
sXmlDocContent = sXmlDocContent & "</processorcheck>"
' close the xml string and return
sXmlDocContent = sXmlDocContent & "</dataset>"


' return pass or fail
IF fSuccess = 1 Then
	WScript.Echo PASSED_CHECK & "|" & sXmlDocContent & "|" & nPassing & "|" & nFailing & "|" & nUnknown
	WScript.Quit PASSED_CHECK
Else
	WScript.Echo FAILED_CHECK & "|" & sXmlDocContent & "|" & nPassing & "|" & nFailing & "|" & nUnknown
	WScript.Quit FAILED_CHECK
End If