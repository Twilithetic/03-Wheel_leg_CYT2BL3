# VSCode Task Flash (probe-rs) 报错分析与修复计划

## 问题描述

运行 `🔥 flash (probe-rs)` 任务时，PowerShell 报错：
```
probe_rs=info: The term 'probe_rs=info' is not recognized as a name of a cmdlet, function, script file, or executable program.
```

但 flash 实际上成功了（Erasing ✔、Programming ✔、Finished）。

## 问题分析

### 当前 tasks.json 配置（第56-68行）

```json
{
    "label": "🔥 flash (probe-rs)",
    "type": "shell",
    "command": "pwsh.exe",
    "args": [
        "-NoProfile",
        "-Command",
        "& { $env:RUST_LOG='probe_rs=info'; & '${workspaceFolder}\\tools\\...\\probe-rs.exe' download ... }"
    ]
}
```

### 根本原因：VSCode args 引号机制与 PowerShell 单引号冲突

1. **VSCode 的 args 引用机制**（来源：[官方文档 v1.22 Release Notes](https://code.visualstudio.com/updates/v1_22) 和 [Tasks 文档](https://code.visualstudio.com/docs/debugtest/tasks)）

   VSCode 在处理 `type: "shell"` 任务的 `args` 时，会自动对含特殊字符的参数施加**引号规则**：
   - PowerShell 默认使用 **strong quoting**：单引号 `'`
   - cmd.exe 默认使用 **strong quoting**：双引号 `"`

2. **冲突发生过程**

   当 VSCode 处理这个 args 数组时，由于参数是传递给 pwsh.exe 的完整命令字符串，VSCode 会尝试用**单引号**包裹整个 `-Command` 的参数值：
   ```
   pwsh.exe -NoProfile -Command '& { $env:RUST_LOG='probe_rs=info'; & ... }'
   ```
   
   注意！PowerShell 的 `-Command` 参数值中的 `$env:RUST_LOG='probe_rs=info'` 里已经包含单引号，VSCode 外面的单引号在 `='` 处被**提前终止**了，导致 `probe_rs=info` 被 PowerShell 当作一个**命令名称**来执行，于是报错 "not recognized as a name of a cmdlet"。

3. **为什么 flash 还是成功了？**
   
   因为引号冲突只影响了 `$env:RUST_LOG='probe_rs=info'` 这个环境变量赋值，后面的 probe-rs.exe 调用（使用另一层单引号包裹路径）虽然也不完美，但恰好能正常工作。所以 RUST_LOG 环境变量没有被设置，probe-rs 以默认日志级别运行了 flash。

### 技术细节：VSCode args 引号机制

来源：https://code.visualstudio.com/docs/debugtest/tasks 和 https://code.visualstudio.com/updates/v1_22

| 引号类型 | PowerShell | cmd.exe | bash/Linux |
|---------|-----------|---------|-----------|
| **strong** (抑制求值) | 单引号 `'` | 双引号 `"` | 单引号 `'` |
| **weak** (允许求值) | 双引号 `"` | 双引号 `"` | 双引号 `"` |
| **escape** | 反引号 `` ` `` | N/A | 反斜杠 `\` |

VSCode 默认对包含空格的命令使用 **strong quoting**，对于 args 也默认使用 **strong quoting**。

## 解决方案

### 方案一（推荐 ⭐）：使用 `options.env` 设置环境变量

**原理**：将 RUST_LOG 环境变量从 PowerShell 命令行移到 `options.env` 中。VSCode 的 `CommandOptions.env` 会正确地将环境变量传递给子进程，完全绕过引号问题。

**依据**：官方 tasks.json schema（https://code.visualstudio.com/docs/reference/tasks-appendix）定义：
```typescript
interface CommandOptions {
    env?: { [key: string]: string };  // 传递给程序/shell 的环境变量
}
```

StackOverflow 专家 mklement0 也推荐此方法：
> "Use an aux. environment variable, which bypasses any quoting/escaping concerns"

**修改后**：
```json
{
    "label": "🔥 flash (probe-rs)",
    "type": "shell",
    "command": "pwsh.exe",
    "args": [
        "-NoProfile",
        "-Command",
        "& '${workspaceFolder}\\tools\\probe-rs-src\\target\\release\\probe-rs.exe' download --chip CYT2BL3BAS --protocol swd --speed 100 --binary-format elf '${workspaceFolder}\\build\\firmware.elf'"
    ],
    "options": {
        "env": {
            "RUST_LOG": "probe_rs=info"
        }
    },
    "group": {"kind": "test", "isDefault": true},
    "dependsOn": ["🔨 build"],
    "presentation": {"reveal": "always", "panel": "dedicated"},
    "problemMatcher": []
}
```

### 方案二：使用 `type: "process"` 直接调用

将 type 从 `"shell"` 改为 `"process"`，完全跳过 VSCode 的 shell 引号层：
```json
{
    "label": "🔥 flash (probe-rs)",
    "type": "process",
    "command": "${workspaceFolder}\\tools\\probe-rs-src\\target\\release\\probe-rs.exe",
    "args": [
        "download", "--chip", "CYT2BL3BAS",
        "--protocol", "swd", "--speed", "100",
        "--binary-format", "elf",
        "${workspaceFolder}\\build\\firmware.elf"
    ],
    "options": {
        "env": { "RUST_LOG": "probe_rs=info" }
    }
}
```
更简洁但改变了任务结构。暂时不推荐，因为 build 任务仍然用 cmd.exe shell。

### 方案三：强制使用 weak quoting

```json
"args": [
    "-NoProfile",
    "-Command",
    {
        "value": "& { $env:RUST_LOG=\"probe_rs=info\"; & '...' }",
        "quoting": "weak"
    }
]
```
但此方案更复杂且难以维护。

## 第二轮优化：能否像 rebuild 一样把 shell 移到 `options.shell`？

### 用户问题
> flash 的 command 是不是可以不用 pwsh.exe，把 shell 移到 options 里像 rebuild 一样？

### 答案：可以！但更好的做法是直接用 `type: "process"` ❗

先对比 `rebuild` 和 `flash` 的本质区别：

| | 🔄 rebuild | 🔥 flash |
|---|---|---|
| **实际要运行的程序** | `make` → 一个 **shell 命令** | `probe-rs.exe` → 一个 **原生可执行文件** |
| **是否需要 shell 解释** | ✅ 是，`make` 需要 cmd.exe 来执行 | ❌ 否，`probe-rs.exe` 可以直接运行 |
| **最佳 task type** | `"shell"` + `options.shell` | `"process"`（无需 shell！） |

### 证据：官方 Schema 定义

来源：https://code.visualstudio.com/docs/reference/tasks-appendix

```typescript
interface TaskDescription {
  /**
   * The type of a custom task. Tasks of type "shell" are executed
   * inside a shell (e.g. bash, cmd, powershell, ...)
   */
  type: 'shell' | 'process';

  /**
   * The command to execute. If the type is "shell" it should be the full
   * command line including any additional arguments passed to the command.
   */
  command: string;

  /**
   * Additional arguments passed to the command.
   * Should be used if type is "process".   👈 注意这句！
   */
  args?: string[];
}

interface CommandOptions {
  /**
   * The environment of the executed program or shell. If omitted
   * the parent process' environment is used.
   */
  env?: { [key: string]: string };

  /**
   * Configuration of the shell when task type is `shell`   👈 仅对 shell 类型有效！
   */
  shell: {
    executable: string;   // 例如 "cmd.exe", "pwsh.exe"
    args?: string[];      // 例如 ["/c"], ["-NoProfile", "-Command"]
  };
}
```

### 官方文档原文（tasks 页）

> **type**: For a custom task, this can either be `shell` or `process`. If `shell` is specified, the command is interpreted as a shell command. If `process` is specified, the command is interpreted as a **process to execute**.
>
> **options**: Override the defaults for `cwd` (current working directory), `env` (environment variables), or `shell` (default shell).

关键词：
- `type: "process"` = "the command is interpreted as a **process to execute**" → 直接运行 exe
- `type: "shell"` + `options.shell` = "the command is a **shell command**" → 需要 shell 来解析
- `args` 文档说："**Should be used if type is 'process'**"
- `options.env` 对 `"shell"` 和 `"process"` **都有效**

### 结论：flash 任务的最佳写法

```json
{
    "label": "🔥 flash (probe-rs)",
    "type": "process",                          // 👈 直接运行 exe，不需要 shell
    "command": "${workspaceFolder}\\tools\\probe-rs-src\\target\\release\\probe-rs.exe",
    "args": [
        "download",
        "--chip", "CYT2BL3BAS",
        "--protocol", "swd",
        "--speed", "100",
        "--binary-format", "elf",
        "${workspaceFolder}\\build\\firmware.elf"
    ],
    "options": {
        "env": {
            "RUST_LOG": "probe_rs=info"         // 👈 env 对 process 类型同样有效
        }
    },
    "group": {"kind": "test", "isDefault": true},
    "dependsOn": ["🔨 build"],
    "presentation": {"reveal": "always", "panel": "dedicated"},
    "problemMatcher": []
}
```

### 为什么比 rebuild 模式更优？

| 对比维度 | rebuild 模式 (shell) | flash 推荐 (process) |
|---------|---------------------|---------------------|
| 间接层 | `cmd.exe /c` → `make` | 直接运行 `probe-rs.exe` |
| 引号风险 | 受 shell 引号规则影响 | **零引号问题** |
| 性能 | 多一层 shell 进程 | 无额外开销 |
| 环境变量 | `options.env` | `options.env`（同） |
| VSCode 干扰 | args 会被 VSCode 加引号 | args **原样传递**给进程 |

---

## 同步优化 `📋 probe-rs info` 任务

两个 probe-rs info 任务（第74-84行、第86-95行）也使用 `pwsh.exe` 包装，且存在**标签重名**问题（后者覆盖前者）。一并改为 `type: "process"`。

---

## 操作步骤

1. ✅ ~~第一轮：移出 `$env:RUST_LOG=...` 到 `options.env`~~（已完成）
2. 🔄 第二轮：将 flash 和 probe-rs info 改为 `type: "process"`，去掉 pwsh.exe 包装
3. 🔄 区分两个 probe-rs info 任务的标签名
4. ⏳ 测试

## 参考文档

- [VSCode Tasks 官方文档](https://code.visualstudio.com/docs/debugtest/tasks)
- [VSCode Tasks Schema](https://code.visualstudio.com/docs/reference/tasks-appendix)
- [VSCode v1.22 Release Notes - Improved argument quoting](https://code.visualstudio.com/updates/v1_22)
- [StackOverflow: VSCode shell task escaping](https://stackoverflow.com/questions/67171114/vscode-shell-task-escaping-single-quotes)
- [GitHub Issue #72039: double quotes removed in PowerShell tasks](https://github.com/microsoft/vscode/issues/72039)
