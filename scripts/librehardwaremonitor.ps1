function Convert-LhmValue {
    param([object]$Value)

    if ($null -eq $Value) { return $null }

    $text = [string]$Value
    if ([string]::IsNullOrWhiteSpace($text)) { return $null }

    # LibreHardwareMonitor display values may look like:
    # "47.0 °C", "12.4 W", "2200 RPM", "35.1 %".
    # Sensor API JSON may also contain plain numeric values.
    $normalized = $text.Trim().Replace(",", ".")
    if ($normalized -match '[-+]?\d+(?:\.\d+)?') {
        return [double]::Parse(
            $Matches[0],
            [System.Globalization.CultureInfo]::InvariantCulture
        )
    }

    return $null
}

function Get-LhmLeafSensors {
    param(
        [Parameter(Mandatory=$true)]
        [object]$Node,
        [string]$ParentPath = ""
    )

    $name = if ($Node.Text) { [string]$Node.Text } else { "" }
    $path = if ([string]::IsNullOrWhiteSpace($ParentPath)) {
        $name
    } elseif ([string]::IsNullOrWhiteSpace($name)) {
        $ParentPath
    } else {
        "$ParentPath > $name"
    }

    $children = @($Node.Children)

    if ($children.Count -gt 0) {
        foreach ($child in $children) {
            Get-LhmLeafSensors -Node $child -ParentPath $path
        }
        return
    }

    if (-not $Node.SensorId -and -not $Node.Type) {
        return
    }

    [PSCustomObject]@{
        sensor_id = [string]$Node.SensorId
        sensor_type = [string]$Node.Type
        name = $name
        path = $path
        value = Convert-LhmValue $Node.Value
        min = Convert-LhmValue $Node.Min
        max = Convert-LhmValue $Node.Max
        raw_value = [string]$Node.Value
    }
}

function Get-LhmSnapshot {
    param(
        [string]$BaseUrl = "http://127.0.0.1:8085"
    )

    $url = $BaseUrl.TrimEnd("/") + "/data.json"

    try {
        $data = Invoke-RestMethod -Uri $url -Method Get -TimeoutSec 3
        $sensors = @(Get-LhmLeafSensors -Node $data)

        foreach ($sensor in $sensors) {
            [PSCustomObject]@{
                timestamp = (Get-Date).ToString("o")
                sensor_id = $sensor.sensor_id
                sensor_type = $sensor.sensor_type
                name = $sensor.name
                path = $sensor.path
                value = $sensor.value
                min = $sensor.min
                max = $sensor.max
                raw_value = $sensor.raw_value
            }
        }
    } catch {
        throw "LibreHardwareMonitor API unavailable at $url : $($_.Exception.Message)"
    }
}
