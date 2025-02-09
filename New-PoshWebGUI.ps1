Function Start-PoshWebGUI ($ScriptBlock)
{
    # We create a scriptblock that waits for the server to launch and then opens a web browser control
    $UserWindow = {
            
            # Wait-ServerLaunch will continually repeatedly attempt to get a response from the URL before continuing
            function Wait-ServerLaunch
            {

                try {
                    $url="http://localhost:8000/"
                    $Test = New-Object System.Net.WebClient
                    $Test.DownloadString($url);
                }
                catch
                { start-sleep -Seconds 1; Wait-ServerLaunch }
 
            }

            Wait-ServerLaunch
            [void][System.Reflection.Assembly]::LoadWithPartialName('presentationframework')
            [xml]$XAML = @'
            <Window
                xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
                xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
                Title="PowerShell HTML GUI" WindowStartupLocation="CenterScreen">

                    <WebBrowser Name="WebBrowser"></WebBrowser>

            </Window>
'@

            #Read XAML
            $reader=(New-Object System.Xml.XmlNodeReader $xaml) 
            $Form=[Windows.Markup.XamlReader]::Load( $reader )
            #===========================================================================
            # Store Form Objects In PowerShell
            #===========================================================================
            $WebBrowser = $Form.FindName("WebBrowser")

            $WebBrowser.Navigate("http://localhost:8000/")

            $Form.ShowDialog()
            Start-Sleep -Seconds 1

            # Once the end user closes out of the browser we send the kill url to tell the server to shut down.
            $url="http://localhost:8000/kill"
            (New-Object System.Net.WebClient).DownloadString($url);
    }
 
    $RunspacePool = [RunspaceFactory]::CreateRunspacePool()
    $RunspacePool.ApartmentState = "STA"
    $RunspacePool.Open()
    $Jobs = @()
 

       $Job = [powershell]::Create().AddScript($UserWindow).AddArgument($_)
       $Job.RunspacePool = $RunspacePool
       $Jobs += New-Object PSObject -Property @{
          RunNum = $_
          Pipe = $Job
          Result = $Job.BeginInvoke()
       }


    # Create HttpListener Object
    $SimpleServer = New-Object Net.HttpListener

    # Tell the HttpListener what port to listen on
    #    As long as we use localhost we don't need admin rights. To listen on externally accessible IP addresses we will need admin rights
    $SimpleServer.Prefixes.Add("http://localhost:8000/")

    # Start up the server
    $SimpleServer.Start()

    while($SimpleServer.IsListening)
    {
        Write-Host "Listening for request"
        # Tell the server to wait for a request to come in on that port.
        $Context = $SimpleServer.GetContext()

        #Once a request has been captured the details of the request and the template for the response are created in our $context variable
        Write-Verbose "Context has been captured"

        # $Context.Request contains details about the request
        # $Context.Response is basically a template of what can be sent back to the browser
        # $Context.User contains information about the user who sent the request. This is useful in situations where authentication is necessary


        # Sometimes the browser will request the favicon.ico which we don't care about. We just drop that request and go to the next one.
        if($Context.Request.Url.LocalPath -eq "/favicon.ico")
        {
            do
            {

                    $Context.Response.Close()
                    $Context = $SimpleServer.GetContext()

            }while($Context.Request.Url.LocalPath -eq "/favicon.ico")
        }

        # Creating a friendly way to shutdown the server
        if($Context.Request.Url.LocalPath -eq "/kill")
        {

                    $Context.Response.Close()
                    $SimpleServer.Stop()
                    break

        }
    
        $Context.Request
        # Handling different URLs

        $result = try {.$ScriptBlock} catch {$_.Exception.Message}

        if($null -ne $result) {
            if($result -is [string]){
                
                Write-Verbose "A [string] object was returned. Writing it directly to the response stream."

            } else {

                Write-Verbose "Converting PS Objects into JSON objects"
                $result = $result | ConvertTo-Json
                
            }
        }

        Write-Host "Sending response of $Result"

        # We convert the result to bytes from ASCII encoded text
        $buffer = [System.Text.Encoding]::ASCII.GetBytes($Result)

        # We need to let the browser know how many bytes we are going to be sending
        $context.Response.ContentLength64 = $buffer.Length

        # We send the response back to the browser
        $context.Response.OutputStream.Write($buffer, 0, $buffer.Length)

        # We close the response to let the browser know we are done sending the response
        $Context.Response.Close()

        $Context.Response
    }

}
Start-PoshWebGUI -ScriptBlock {

    switch ($Context.Request.Url.LocalPath)
    {

        "/loadProcesses" { Get-Process $Context.Request.QueryString["ProcessName"] | Select-Object cpu,name | ConvertTo-Html | Out-String }
        "/loadServices" { Get-Service $Context.Request.QueryString["ServiceName"] | Select-Object Status,Name,DisplayName | ConvertTo-Html | Out-String }
        
        default { @"
        
        <h1>Simple Task Manager</h1>
        
        <form action="/loadProcesses">
            <h2>Load Processes</h2>
            <p>Filter by name</p>
            <input name="ProcessName"></input>
            <button type="submit">Submit</button>
            
        </form>

        <form action="/loadServices">
            <h2>Load Services</h2>
            <p>Filter by name</p>
            <input name="ServiceName"></input>
            <button type="submit">Submit</button>
            
        </form>      
        
"@ }

    }

}
