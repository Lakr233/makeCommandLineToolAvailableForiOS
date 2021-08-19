#!/bin/bash

set -exo

scriptName="makeMyCommandLineToolAvailable"

tempDirsFile="$(mktemp -d -t $scriptName)/tempdirs"
touch "$tempDirsFile"
backupFileExt=".backup"

function panic() {
    exit "$1"
}

function getTempDir() {
    local tempDir
    tempDir=$(mktemp -d -t $scriptName) ||
        panic $? "Failed to create temporary directory"
    echo "$tempDir" >>"$tempDirsFile" ||
        panic $? "Failed to echo into $tempDirsFile"
    echo "$tempDir"
}

function copyFile() {
    cp -f "$1" "$2" ||
        panic $? "Failed to copy file $1 to $2"
}

# 备份原文件
function requireBackup() {
    [[ ! -f "$1" || -f "${1}${backupFileExt}" ]] ||
        copyFile "$1" "${1}${backupFileExt}"
}

# 验证是否存在文件
function requireFile() { # args: filePath [, touchFileIfNotFound]
    local filePath="$1"
    local touchFileIfNotFound="$2"

    if [[ ! -f "$filePath" ]]; then
        if [[ $touchFileIfNotFound == "true" ]]; then

            touch "$filePath" ||
                panic $? "Failed to touch $filePath"

        else
            panic 1 "File $filePath not found"
        fi
    fi
}

# 获取SDK信息
function getSdkProperty() {

    local sdk="$1"
    local propertyName="$2"

    propertyValue=$(xcodebuild -version -sdk "$sdk" "$propertyName") ||
        panic $? "Failed to get $sdk SDK property $propertyName"

    [[ $propertyValue != "" ]] ||
        panic 1 "Value of $sdk SDK property $propertyName cannot be empty"

    # return #
    echo "$propertyValue"
}

# 判断文件是否包含内容
function doesFileContain() { # args: filePath, pattern

    local filePath="$1"
    local pattern="$2"
    local perlValue
    local funcReturn

    perlValue=$(perl -ne 'if (/'"$pattern"'/) { print "true"; exit; }' "$filePath") ||
        panic $? "Failed to perl"

    if [[ $perlValue == "true" ]]; then
        funcReturn="true"
    else
        funcReturn="false"
    fi

    # return #
    echo $funcReturn
}

# 从spec读取内容
function readXcodeSpecificationById() { #args: filePath, id
    local filePath="$1"
    local id="$2"
    content=$(/usr/libexec/PlistBuddy -x -c Print "$filePath") ||
        panic $? "Failed to get $filePath content"
    for ((i = 0; i <= 1; i++)); do
        dict=$(/usr/libexec/PlistBuddy -x -c "Print $i" "$filePath")
        if echo "$dict" | grep -qE "<string>$id</string>"; then
            echo "$dict"
        fi
    done
}

# 往spec文件写入内容
function writeDictToSpecification() { #args: filePath, content
    local filePath="$1"
    local content="$2"
    tempfile=$(getTempDir)/dictfile
    echo "$content" >>"$tempfile"
    /usr/libexec/PlistBuddy -x -c 'add 0 dict' "$filePath" >/dev/null
    /usr/libexec/PlistBuddy -x -c "merge $tempfile 0" "$filePath" >/dev/null
}

# now, iphoneos command line tools
iosSdkPlatformPath=$(getSdkProperty iphoneos PlatformPath)
macosSdkPlatformPath=$(getSdkProperty macosx PlatformPath)
specificationFile=$(cd "$iosSdkPlatformPath"/../../.. && pwd)/PlugIns/IDEiOSSupportCore.ideplugin/Contents/Resources/Embedded-Device.xcspec

requireFile "$specificationFile" false

# backup
requireBackup "$specificationFile"

hasPackageTypeForCommandLineTool=$(doesFileContain "$specificationFile" 'com.apple.package-type.mach-o-executable')
hasProductTypeForCommandLineTool=$(doesFileContain "$specificationFile" 'com.apple.product-type.tool')

macosxSDKSpecificationsPath=$macosSdkPlatformPath/Developer/Library/Xcode/PrivatePlugIns/IDEOSXSupportCore.ideplugin/Contents/Resources

# fallback if not real
if [ ! -f "$macosxSDKSpecificationsPath" ]; then
    echo "$FILE does not exist, fallback to older options"
    macosxSDKSpecificationsPath=$macosSdkPlatformPath/Developer/Library/Xcode/Specifications
fi

packageTypesForMacOSXPath="$macosxSDKSpecificationsPath/MacOSX Package Types.xcspec"
productTypesForMacOSXPath="$macosxSDKSpecificationsPath/MacOSX Product Types.xcspec"

requireFile "$packageTypesForMacOSXPath" false
requireFile "$productTypesForMacOSXPath" false

if [[ $hasPackageTypeForCommandLineTool != "true" ]]; then
    machoDict=$(readXcodeSpecificationById "$packageTypesForMacOSXPath" "com.apple.package-type.mach-o-executable")
    writeDictToSpecification "$specificationFile" "$machoDict"
fi

if [[ $hasProductTypeForCommandLineTool != "true" ]]; then
    toolDict=$(readXcodeSpecificationById "$productTypesForMacOSXPath" "com.apple.product-type.tool")
    writeDictToSpecification "$specificationFile" "$toolDict"
fi
