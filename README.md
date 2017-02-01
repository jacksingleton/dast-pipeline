# Notes on the current state of DAST tooling in automated delivery pipelines

[DAST](http://www.gartner.com/it-glossary/dynamic-application-security-testing-dast/) (Dynamic Application Security Testing) tools analyze running applications in order to identify common vulnerabilities. They generally learn the normal interaction patterns by observing the application in use, alert on any vulnerabilities they can detect through regular usage (passive scan) and then replay traffic modified to attempt a variety of attacks (active scan).

For web applications, two common DAST tools are [Burp Suite](https://portswigger.net/) (commercial, by PortSwigger) and [Zed Attack Proxy](https://www.owasp.org/index.php/OWASP_Zed_Attack_Proxy_Project), or ZAP (open source, an OWASP project).

Both of these tools have been designed primarily to augment manual testing, but also provide API's that could allow integration into an automated delivery pipeline.

It's becoming common to talk about doing this as a way that delivery teams can take more responsibility for application security, so I took a look at how practical it currently is to use these tools in an automated way. While it is definitely possible, there were a number of challenges that we need to overcome before recommending this as a solid strategy for all or most delivery teams.

## Basic Overview

The general idea is to:

1) Run functional/end-to-end/feature tests through the http proxy provided by Burp/ZAP

1) Trigger an active scan through the Burp/ZAP API

1) Export the report as a build artifact in HTML and XML

ZAP includes an http api in the default distribution. I checked the 'disable api key' setting in the GUI for the assessment.

Burp Suite does not include an http api by default, but some people at vmware wrote [an extension](https://github.com/vmware/burp-rest-api).

## In Process Tests

The rails application I used for this assessment has a healthy suite of Capybara tests which start the entire app (connected to a test sqlite database) and step through a number of user journeys. But, in order to speed up the tests, they ran in process using Capybara's default [RackTest driver](https://github.com/teamcapybara/capybara#racktest), which makes it impossible to send test traffic through an http proxy.

To work around this, I switched the driver to the selenium driver. However, this broke test isolation as database transaction rollbacks had been used to keep data from each test separate (quite common for in process tests). I had to switch from transaction isolation to using truncation with [DatabaseCleaner](https://github.com/DatabaseCleaner/database_cleaner). This worked for some of the tests, but caused others to fail.

Lesson: if the application doesn't have a functional test suite that runs *out of process*, a decent amount of work could be required to send traffic through a proxy.

## Test Specific Data

The test app, like most I have seen, uses a separate data set for each test. This means that if we try to run an active scan after running an entire test suite, most attacks will fail because they are acting on data that no longer exists.

Instead, I created a new session before each test and ran the active scan after each test, before clearing the database.

This worked, but meant that I had to export a separate report for each test. Besides resulting in lots of files, this also meant that zap/burp could not collapse multiple instances of the same vulnerability.
