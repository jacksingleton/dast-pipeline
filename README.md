# Notes on the current state of DAST tooling in automated delivery pipelines

[DAST](http://www.gartner.com/it-glossary/dynamic-application-security-testing-dast/) (Dynamic Application Security Testing) tools analyze running applications in order to identify common vulnerabilities. They generally learn the normal interaction patterns by observing the application in use, alert on any vulnerabilities they can detect through regular usage (passive scan) and then replay traffic modified to attempt a variety of attacks (active scan).

For web applications, two common DAST tools are [Burp Suite](https://portswigger.net/) (commercial, by PortSwigger) and [Zed Attack Proxy](https://www.owasp.org/index.php/OWASP_Zed_Attack_Proxy_Project), or ZAP (open source, an OWASP project).

Both of these tools have been designed primarily to augment manual testing, but also provide API's that could allow integration into an automated delivery pipeline.

It's becoming common to talk about doing this as a way that delivery teams can take more responsibility for application security, so I took a look at how practical it currently is to use these tools in an automated way. While it is definitely possible, there were a number of challenges that we need to overcome before recommending this as a solid strategy for all or most delivery teams.

## Basic Setup

The general idea is to:

1. Run functional/end-to-end/feature tests through the http proxy provided by Burp/ZAP
1. Trigger an active scan through the Burp/ZAP API
1. Export the report as a build artifact in HTML and XML

ZAP includes an http api in the default distribution. I checked the 'disable api key' setting in the GUI for the assessment. It's looks quite complete.

Burp Suite does not include an http api by default, but some people at vmware wrote [burp-rest-api](https://github.com/vmware/burp-rest-api) that implements one. It's a well designed RESTy api (especially compared to ZAPs which consists of all GETs) but is less complete.

Both ZAP and Burp can be ran in headless mode. They can also be ran in GUI mode while still exposing the API. I found this useful while debugging the setup as the results of the API calls (in the sitemap, scan queue, scope, etc) are immediatly visible.

## In Process Tests

The rails application I used for this assessment has a healthy suite of Capybara tests which start the entire app (connected to a test sqlite database) and step through a number of user journeys. But, in order to speed up the tests, they ran in process using Capybara's default [RackTest driver](https://github.com/teamcapybara/capybara#racktest), which makes it impossible to send test traffic through an http proxy.

To work around this, I switched the driver to the selenium driver. However, this broke test isolation as database transaction rollbacks had been used to keep data from each test separate (quite common for in process tests). I had to switch from transaction isolation to using truncation with [DatabaseCleaner](https://github.com/DatabaseCleaner/database_cleaner). This worked for some of the tests, but caused others to fail.

Lesson: if the application doesn't have a functional test suite that runs *out of process*, a decent amount of work could be required to send traffic through a proxy.

## Test Specific Data

The test app, like most I have seen, uses a separate data set for each test. This means that if we try to run an active scan after running an entire test suite, most attacks will fail because they are acting on data that no longer exists.

Instead, for my first pass, I created a new session before each test and ran the active scan after each test, before clearing the database.

**TODO** burp didn't have the new session resource

This worked, but meant that I had to export a separate report for each test. Besides resulting in lots of files, this also meant that zap/burp could not collapse multiple instances of the same vulnerability.

Things could also be complicated if the tests were designed to build on each other's data. In this case, the active scan could delete or otherwise change data from one test, getting in the way of the test test due to run next.

## Live Active Scan

ZAP and Burp both include a feature to conduct an active scan in real time as requests/responses are sent through the proxy. Burp calls this a 'Live Active Scan' and ZAP calls it 'Attack Mode'.

The advantage with this is that we don't have to create a new session (and report) for each test as long as we wait for the active scanning to complete before moving on to the next test.

Unfortunately, burp-rest-api does not have a resource for retrieving the progress of the live active scan (the queue for the live active scan is separate from active scans triggered through the gui and api). One could probably be added without too much trouble, but this was more of an investment than I was willing to make.

I did manage to make it work with ZAP, although the api method I needed wasn't obvious. As with Burp, the live active scan queue is separate from the triggered active scan queue. But, I found that the `/JSON/pscan/view/recordsToScan` method includes the live active scan queue (even if it's under 'pscan', meaning passive scan). The number fluxuates a lot, and sometimes hits zero briefly while the scanning is still active, so I used a spin check to wait until the queue has been at zero for five seconds before moving on to the next test.

## Pipeline Prior Art

The [OWASP AppSec Pipeline](https://www.owasp.org/index.php/OWASP_AppSec_Pipeline#tab=Main) project has similar goals, but on closer look it seems their approach is different from what I have in mind. From their [pipline design patterns](https://www.owasp.org/index.php/OWASP_AppSec_Pipeline#tab=Pipeline_Design_Patterns) page:

'''
customers request AppSec services such as dynamic, static or manual assessments from the AppSec team
'''

I'm not interested in making it easier for a centralized AppSec team to manage scan results for many delivery teams, I'm trying to see how feasible it is for delivery teams *themselves* to integrate security checks into their pipeline. If some expertise is needed to interpret results, decide on or test a mitigation, etc. then I have no problem with pulling someone in from a horizonatal (security) group. But when a check fails, the delivery team themselves should respond to their light going red.

In the same vein, we thought [ThreadFix](http://www.denimgroup.com/threadfix/) could be useful for aggregating and managing scan results. However, it also looks to be targeted more at centralized AppSec teams:

'''
ThreadFix allows security teams to create a consolidated view of applications and vulnerabilities, prioritize application risk decisions based on data, and transition application vulnerabilities to developers
'''

Also, Denim Group has decided to [discontinue work on the open source ThreadFix codebase](https://groups.google.com/d/msg/threadfix/bn2nnoWYhlg/Ma_EcrPQBgAJ), and the future of the open source project looks quite uncertain.

[Mozilla Minion](https://wiki.mozilla.org/Security/Projects/Minion) looks slightly more delivery team focused, but still seems to work on the assumption that there will be one security scanning server (Minion) that can be pointed at a number of applications. This contrasts with our approach of integrating security testing into the pipeline owned by a delivery team, integrated with functional tests also owned by that team.

## Result Quality

In the end, the results generated for the application I used to test were OK.

ZAP included some pretty surprising false positives, including a Buffer Overflow alert (not high on my list of things to check for in a Rails web application!).

Another shortcoming is that ZAP does not include the request/response details in it's reports. When using the GUI manually this isn't so much of a problem, but when running headless, the only artifact you are left with is the report. Without knowing exactly what the scanner alerted on verifying and addressing results can be difficult.

Burp had less false positives, the main one being an XSS alert which was very close to legitimate. It turned out that the application was allowing <a> tags to be submitted as input and then rendered (unencoded) on the response page. However, when I investigated further it appeared that the tag had been purposely whitelisted in an html sanitizer. Other tags were not allowed, as well as dangerous attributes like onclick, and only http/https url schemes were allowed in the href attribute.

Burb also included full request/response data in the report, as well as quite impressive descriptions and remediation advice.

## Scan Time

The downside of Burps rigorous checks is that the scanning took significantly longer (> twice the time) than ZAP, even on the fastest scan setting. If we want immediate feedback and/or a gate in the build pipeline this could be a problem, but for nightly scans it's probably acceptable.

## Addressing False Positives
