# Smart API Manager

本项目为基于 PowerShell 的 API 管理脚本。

## 目录结构

- `./`  
    本目录包含所有 PowerShell API 管理相关脚本和工具。

## 功能

- 管理和调用 API
- 支持外部文件配置参数
- 支持邮箱服务器发送功能
- 历史数据日志切割
- 程序生成数据与配置数据分离
- 数据恢复机制，当缺少历史数据文件和程序生成数据文件时会自动修复
- 可视化程序输出日志，便于排查问题
- 可扩展性强，便于集成到自动化流程

## 使用方法

1. 进入本目录：

     ```PowerShell
        cd .\
        cp config.json.example config.json
     ```

2. 运行 PowerShell 脚本：

     ```PowerShell
        .\smart-api.ps1

        #单次模式
        .\smart-api.ps1 -SingleMode
     ```

## 配置文件说明(config.json)

"maxDailyRequests": 35,          // Require

"randomNumber": 10,              // Optional, default 0

"receiveEMailList": ["aiqubit@hotmail.com","openpicklabs@hotmail.com"], // Require

"timeout": 30,                   // Optional

"requestDelay": 2,               // Optional

"maxHistoryFileSizeMB": 2,       // Optional, default 1

"apiUrl": "`https://xxxx`",   // Require

"headers": {
    "Content-Type": "application/json"              // Optional
},

"requestBody": {
    "template": "default_payload"                   // Optional
},

"emailSettings": {
    "smtpServer": "smtp.qq.com",                    // Require
    "smtpPort": 587,                                // Require
    "enableSsl": true,                              // Require
    "senderEmail": "<xxxxx@qq.com>",                // Require
    "senderPassword": "",                           // Require
    "subject": "QrCode-DING Manager Daily Report"   // Require
}

## 依赖

- PowerShell 7+
- 相关 API 的访问权限

## 贡献

欢迎提交 issue 和 PR 改进本项目。

## 许可证

MIT License
