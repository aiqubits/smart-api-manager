# Email Setup Guide for Smart API Manager

## Overview

The Smart API Manager now includes email reporting functionality that automatically sends daily reports after each execution. This guide explains how to configure and use this feature.

## Configuration

### 1. Email Settings in config.json

Update your `config.json` file to include the following email configuration:

```json
{
    "apiUrl": "https://api.example.com/endpoint",
    "maxDailyRequests": 10,
    "receiveEMail": "your-email@example.com",
    "timeout": 30,
    "headers": {
        "Content-Type": "application/json",
        "Authorization": "Bearer your_token_here"
    },
    "requestBody": {
        "template": "default_payload"
    },
    "emailSettings": {
        "smtpServer": "smtp-mail.outlook.com",
        "smtpPort": 587,
        "enableSsl": true,
        "senderEmail": "your_sender_email@outlook.com",
        "senderPassword": "your_app_password",
        "subject": "Smart API Manager Daily Report"
    }
}
```

### 2. Required Email Settings

- **receiveEMail**: The email address where reports will be sent
- **emailSettings.smtpServer**: SMTP server address (e.g., smtp-mail.outlook.com for Outlook)
- **emailSettings.smtpPort**: SMTP port (usually 587 for TLS)
- **emailSettings.enableSsl**: Enable SSL/TLS encryption (recommended: true)
- **emailSettings.senderEmail**: Email address used to send reports
- **emailSettings.senderPassword**: Password or app password for sender email
- **emailSettings.subject**: Subject line for email reports

### 3. Common SMTP Settings

#### Outlook/Hotmail
```json
"emailSettings": {
    "smtpServer": "smtp-mail.outlook.com",
    "smtpPort": 587,
    "enableSsl": true
}
```

#### Gmail
```json
"emailSettings": {
    "smtpServer": "smtp.gmail.com",
    "smtpPort": 587,
    "enableSsl": true
}
```

#### Yahoo
```json
"emailSettings": {
    "smtpServer": "smtp.mail.yahoo.com",
    "smtpPort": 587,
    "enableSsl": true
}
```

## Security Considerations

### App Passwords

For enhanced security, especially with 2FA enabled accounts:

1. **Outlook/Hotmail**: Generate an app password in your Microsoft account security settings
2. **Gmail**: Enable 2FA and generate an app password in Google Account settings
3. **Yahoo**: Use an app password from Yahoo Account Security settings

### Password Storage

- Never commit actual passwords to version control
- Consider using environment variables or secure credential storage
- Use app passwords instead of main account passwords

## Email Report Content

The email report includes:

1. **Execution Summary**: Overall success/failure status
2. **Today's Statistics**: Total requests, successful requests, failed requests
3. **Current Execution Result**: Details of the current run
4. **Request History**: Table of today's API requests with timestamps and status
5. **System Information**: PowerShell version, machine name, user

## Testing Email Configuration

Use the test script to verify your email configuration:

```powershell
# Test configuration only (no email sent)
.\Test-EmailManager.ps1 -TestConfigOnly -Verbose

# Test configuration and send test email
.\Test-EmailManager.ps1 -Verbose
```

## Troubleshooting

### Common Issues

1. **Authentication Failed**
   - Verify email and password are correct
   - Use app password if 2FA is enabled
   - Check if "less secure apps" need to be enabled (not recommended)

2. **Connection Timeout**
   - Verify SMTP server and port settings
   - Check firewall/antivirus blocking SMTP connections
   - Ensure internet connectivity

3. **SSL/TLS Errors**
   - Verify `enableSsl` setting matches server requirements
   - Try different ports (25, 465, 587)

4. **Email Not Received**
   - Check spam/junk folder
   - Verify recipient email address
   - Check email provider's delivery logs

### Debug Steps

1. Run with verbose output: `.\smart-api.ps1 -Verbose`
2. Test email configuration: `.\Test-EmailManager.ps1 -TestConfigOnly`
3. Check PowerShell execution policy: `Get-ExecutionPolicy`
4. Verify .NET Framework version supports SMTP

## Disabling Email Reports

To disable email reports:

1. Remove `receiveEMail` from config.json, or
2. Remove `emailSettings` section from config.json, or
3. Run in test mode: `.\smart-api.ps1 -TestMode`

## Integration with Main Script

Email reports are automatically sent after each execution of `smart-api.ps1`:

- **Normal Mode**: Email sent after workflow completion
- **Test Mode**: Email sending is skipped
- **Failed Execution**: Email still sent with error details

The email functionality is integrated into the main workflow and will not prevent the script from completing if email sending fails.