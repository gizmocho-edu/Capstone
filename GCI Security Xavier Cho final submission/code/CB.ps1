Param
(
    [string]$hostname, 
    [string]$command,
    [string]$object,
    [string]$key,
    [string]$location,
    [string]$baseURL
)

$coreHeaders = @{
    "X-Auth-Token"=$key;
    "Content-Type"="application/json";
}


function check_active($Session_id){
    $finished = $false
    while($finished -eq $false){
        $statusURL = "$baseURL/api/v1/cblr/session/$Session_id"
        try{
            $statusResponse = Invoke-RestMethod -uri $statusURL -Headers $coreHeaders 
        }
        catch{
            Write-Error "Bad URL"
            exit 1
        }
        if($statusResponse.status -eq "active"){
            $finished = $true
        }
    }
}

function retieve($session_id, $command_id){
    try{
        $url = "$baseURL/api/v1/cblr/session/$session_id/command/$command_id"
        $response = Invoke-RestMethod -uri $url -Headers $coreHeaders
        while($response.status -eq "pending"){
            Start-Sleep -s 1
            $response = Invoke-RestMethod -uri $url -Headers $coreHeaders
        }
    }
    catch{
        
    }

    return $response
}

function find_id($Hostname){
    Write-Host "Grabbing the sensor ID, please wait"
    $url = "$baseURL/api/v1/sensor?hostname=$Hostname"
    $response = Invoke-RestMethod -uri $url -Headers $coreHeaders
    Write-Host $response
    
    if($response.id.GetType() -eq [System.Object[]]){
        Write-Host "Sensor id: ", $response.id[0]
        return $response.id[0]
    }else{
        Write-Host "Sensor id: ", $response.id
        return $response.id 
    }
}

function build_link($Sensor_id){
    try{
        $body = @{
            "sensor_id" = $Sensor_id
        } | ConvertTo-Json
        $url = "$baseURL/api/v1/cblr/session"
        $response = Invoke-RestMethod -Uri $url -Headers $coreHeaders -Method Post -Body $body
        $session_id = $response.id
        Write-Host $session_id
    }
    catch{
        $statusURL = "$baseURL/api/v1/cblr/session"
        $statusResponse = Invoke-RestMethod -uri $statusURL -Headers $coreHeaders
        foreach($session in $statusResponse){
            if(($session.sensor_id -eq $sensor_id) -and (($session.status -eq "pending") -or ($session.status -eq "active"))){
                $session_id = $session.id
                Write-Host $session_id
                break
            }
        }
    }
    check_active($session_id)
    return $session_id
}

function controller($Session_id, $body){
    $url = "$baseURL/api/v1/cblr/session/$Session_id/command"
    $response = Invoke-RestMethod -uri $url -Headers $coreHeaders -Method Post -Body $body
    $command_id = $response.id
    $commandResponse = retieve $Session_id $command_id
    return $commandResponse
}

function run_counter($body){
    Write-Host "Beginning execution..."
    $sensor_id = find_id($hostname)
    $session_id = create_session($sensor_id)
    Write-Host "Session is now active."
    $returnVal = command_handler $session_id $body
    return $returnVal, $session_id
}

function main{
    if($baseURL[$baseURL.length - 1] -eq '/'){
        $baseURL = $baseURL.Substring(0, $baseURL.length - 1)
    }
    switch($command.ToLower()){

        "ps"{
            $body = @{"name"="process list"} | ConvertTo-Json
            $returnVal = run_counter($body)
            if($location){
                echo "" | Out-File $location
                ForEach ($item in $returnVal.processes) {
                    echo $item | Out-File $location -Append
                }
                Write-Host "Results stored: $location"
            }
            else{
                ForEach ($item in $returnVal.processes) {
                    Write-Host $item
                }
            }
        }

        "kill"{
            $body = @{"name"="kill"; "object"=[int]$object} | ConvertTo-Json
            $returnVal = run_counter($body)
        }

        "get"{
            $body = @{"name"="get file"; "object"=$object} | ConvertTo-Json
            $returnVal, $Session_id = run_counter($body) 
            $file_id = $returnVal.file_id
            $url = "$baseURL/api/v1/cblr/session/$Session_id/file/$file_id/content"
            if($object.Contains('/')){
                $output = $location + $object.Substring($object.LastIndexOf("/")+1)
            }
            elseif($object.Contains('\')){
                $output = $location + $object.Substring($object.LastIndexOf("\")+1)
            }
            else{
                Write-Error "Invalid source path: $object"
                exit 1
            }
            write-host $output

            $scriptBlock = {
                param($url, $coreHeaders, $output, $location)
                try{
                    
                    Invoke-RestMethod -Uri $url -Headers $coreHeaders -OutFile $output
                    '''
                    echo $location | Out-File ($location + "status.txt")
                    '''

                }
                catch{
                    echo $url | Out-File $location + "error.txt"
                    
                    echo $_ | Out-File ($location + "error.txt") -Append
                    exit 1
                }
            }
            Start-Job -ScriptBlock $scriptBlock -ArgumentList $url, $coreHeaders, $output, $location
        }

        "isolate"{
            $sensor_id = find_id($hostname)
            $url = "$baseURL/api/v1/sensor/$sensor_id"
            $response = Invoke-RestMethod -Uri $url -Headers $coreHeaders

            if($object.ToLower() -eq "false"){
                $response.network_isolation_enabled = $False
            }
            elseif($object.ToLower() -eq  "true"){
                $response.network_isolation_enabled = $True
            }
            else{
                Write-Error "Invalid parameter"
                exit 1
            }
            $response = Invoke-RestMethod -uri $url -Headers $coreHeaders -Method Put -Body ($response|ConvertTo-Json)
            Write-Host $response
        }

        "delete"{
            $body = @{"name"="delete file"; "object"=$object} | ConvertTo-Json
            $returnVal = run_counter($body)

        }
        "memdump"{
            $body = @{"name"="memdump"; "object"=$object;} | ConvertTo-Json
                Write-Host "Beginning execution..."
                $sensor_id = find_id($hostname)
    
                $session_id = create_session($sensor_id)
                Write-Host "Session is now active."
                Write-Host "Executing $command..."
                $url = "$baseURL/api/v1/cblr/session/$Session_id/command"
                $response = Invoke-RestMethod -uri $url -Headers $coreHeaders -Method Post -Body $body
                $command_id = $response.id

                $scriptBlock = {
                    param($baseURL, $session_id, $command_id, $coreHeaders)
                    try{
                        $url = "$baseURL/api/v1/cblr/session/$session_id/command/$command_id"
                        $response = Invoke-RestMethod -uri $url -Headers $coreHeaders
                        while($response.status -eq "pending"){
                            Start-Sleep -s 1
                            $response = Invoke-RestMethod -uri $url -Headers $coreHeaders
                        }
                    }
                    catch{
                       
                    }
                }
                Start-Job $scriptBlock -ArgumentList $baseURL, $session_id, $command_id, $coreHeaders

        }

        "help"{
            
            exit 0
        }

        default{
            exit 1
        }
    }
}

main

Write-Host "$command executed successfully."
exit 0