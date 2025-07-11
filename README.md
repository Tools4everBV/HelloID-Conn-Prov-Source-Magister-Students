# HelloID-Conn-Prov-Source-magister

| :information_source: Information |
|:---------------------------|
| This repository contains the connector and configuration code only. The implementer is responsible to acquire the connection details such as username, password, certificate, etc. You might even need to sign a contract or agreement with the supplier before implementing this connector. Please contact the client's application manager to coordinate the connector requirements.       |

<br />
 
<p align="center">
  <img src="https://www.tools4ever.nl/connector-logos/magister-logo.png">
</p>

## Table of contents

- [Introduction](#Introduction)
- [Getting started](#Getting-started)
  + [Connection settings](#Connection-settings)
  + [Prerequisites](#Prerequisites)
  + [Remarks](#Remarks)
- [Setup the connector](Setup-The-Connector)
- [Getting help](Getting-help)

## Introduction
The HelloID-Conn-Prov-Source-magister-students is used to retrieve students from Magister.

## Getting started

### Prerequisites
 - URL to the webservice. Example: https://tools4ever.swp.nl:8800
 - username
 - password
 - layoutname
 - magister application manager stand by for importing the layout

### Actions
| Retrieve te data in csv format.


### Connection settings
The following settings are required to connect to the API.

| Setting     | Description |
| ----------- | ----------- |
| Username    | The username   |
| Password    | The password  |
| BaseUrl     |    The URL to the Magister environment. Example: https://tools4ever.swp.nl:8800
| Layout      | Name of the list in Decibel to export
| isDebug     | Debug toggle




### Remarks
 - Data Processing: It categorizes student enrollments by period status (active/future/past), prioritizes the most relevant enrollment per student, and organizes multiple enrollments as contracts with associated details. 
 - Execute on-premises because of IP whitelisting on Magister site
 - The magsiter application manager must create an layout named "tools4ever-leerlingen-actief"
 - The username must be authorized for the layout "tools4ever-leerlingen-actief"
 - The magister application manager must import the contents off the layout "tools4ever-leerlingen-actief" into decibel
 - documentation can be found at https://<tenant>.swp.nl:8800/doc?


## Getting help

> _For more information on how to configure a HelloID PowerShell connector, please refer to our [documentation](https://docs.helloid.com/hc/en-us/articles/360012557600-Configure-a-custom-PowerShell-source-system) pages_

> _If you need help, feel free to ask questions on our [forum](https://forum.helloid.com)_

## HelloID Docs

The official HelloID documentation can be found at: https://docs.helloid.com/
