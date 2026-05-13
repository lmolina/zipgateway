<!-- SPDX-FileCopyrightText: Silicon Laboratories Inc. <https://www.silabs.com/> -->
<!-- SPDX-License-Identifier: LicenseRef-MSLA -->

# Contributing Guideline - Internal Repository

Refer to the [Git User Guide](https://confluence.silabs.com/spaces/IoTApps/pages/652839615/Git+user+guide).

### As a Developer

What to consider when raising a Pull Request:

1. **Use conventional commits**
    https://www.conventionalcommits.org/en/v1.0.0/, also when relevant follow https://dep-team.pages.debian.net/deps/dep3/

2. **Pull Request Naming**
   By default, GitHub uses the branch name as the pull request title. If the branch naming guideline was followed, no changes are needed here.

3. **Check the Reviewer List**
   GitHub assigns reviewers based on the [CODEOWNERS](CODEOWNERS) file.
   Add more reviewers if needed. Do not remove reviewers from the PR. Ask the repository owner for updates to the code owners.

4. **Evaluate the Action Workflow Results**
   The following workflows are included in every repository:
   - **[Coding Convention Check](workflows/00-Check-Code-Convention.yml)**: Analyzes the code formatting and fails if any rules are broken.
   - **[Firmware Build](workflows/02-Build-Firmware.yml)**: Builds the firmware inside the [Dockerfile](../Dockerfile).
   - **[Secret Scanner](workflows/04-TruffleHog-Security-Scan.yml)**: Runs the TruffleHog security scanner to look for API keys and committed secrets.
   - **[SonarQube Analysis](workflows/zz-sonarqube-analysis.yml)**: Runs SonarQube analysis on the project. Refer to the related [Confluence page](https://confluence.silabs.com/display/IoTApps/SQA+-+SonarQube+howTo).

### As a Reviewer

What to consider when reviewing a Pull Request:

- All builds must pass successfully.
- The code must follow the Silicon Labs [coding guidelines](https://github.com/SiliconLabsSoftware/agreements-and-guidelines/blob/main/coding_standard.md).
- Write clear comments. Describe the issue and explain why you disagree (e.g., mistakes, errors, violations of conventions, performance risks, security issues, etc.).
