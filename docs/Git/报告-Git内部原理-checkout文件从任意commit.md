# Git 内部原理：`git checkout <commit> -- <file>` 魔法解析

> 📅 2026-05-06  
> 🏷️ Git 内部原理 / 三棵树模型 / 对象存储

---

## 一、动机：从游离分支"捞"文件到 master

**场景**：仓库处于 detached HEAD 状态（游离分支），想把它上面的某个文件移到 master 分支，但不想要整个 commit 的其他文件。

**命令**：
```bash
git checkout 9915aee -- "docs/报告.md"
```

这条命令只用一个文件就实现了"精准搬运"，既不切换分支（HEAD 不动），也不影响其他文件。本文深入解释它的底层原理。

---

## 二、Git 的"三棵树"模型

Git 内部维护了三个存放代码的地方，理解它们是读懂一切 Git 命令的前提：

```
┌──────────────────────────────────────────────────────────────┐
│                  Git 三棵树 (Three Trees)                     │
├────────────────┬──────────────────┬──────────────────────────┤
│ HEAD           │ Index (暂存区)    │ Working Directory (工作区)│
│ 上次 commit 的  │ git add 写入这里   │ 你实际看到的文件            │
│ 永久快照        │ 下次 commit 的来源 │                          │
├────────────────┼──────────────────┼──────────────────────────┤
│ 存在 .git 里    │ .git/index 文件   │ 普通文件系统               │
│ 不可直接修改     │ 可被 checkout 改  │ 可随便改                  │
└────────────────┴──────────────────┴──────────────────────────┘
```

| 命令 | 影响范围 |
|------|---------|
| `git add` | Working Dir → Index |
| `git commit` | Index → HEAD (新建 commit) |
| `git checkout <branch>` | HEAD + Index + Working Dir 全部更新 |
| `git checkout <commit> -- <file>` | ⚠️ 只更新 Index + Working Dir，HEAD 不动 |

---

## 三、`git checkout <commit> -- <file>` 的三步底层流程

```
git checkout 9915aee -- "docs/报告.md"

    ┌─────────────────────┐
    │  Commit: 9915aee     │  ← 不变！HEAD 不指向这里
    │  ┌─────────────────┐ │
    │  │ Tree 对象        │ │
    │  │ ├─ Blob: main.c │ │
    │  │ ├─ Blob: README │ │
    │  │ └─ Blob: 报告.md │◀┼──── 只取这个
    │  └─────────────────┘ │
    └─────────┬────────────┘
              │
    ┌─────────┼─────────┐
    ▼                   ▼
  Index              Working Dir
 (暂存区)             (磁盘上)
  ┌────────┐          ┌────────┐
  │ 报告.md │          │ 报告.md │  ← 内容来自 9915aee
  └────────┘          └────────┘

  HEAD → master  (不动！依然指向 master)
```

### 步骤分解

| 步骤 | Git 内部动作 |
|------|-------------|
| **① 定位** | 解析 commit `9915aee` 的 SHA → 找到其 tree 对象的 SHA |
| **② 查找** | 在 tree 对象中按路径 `docs/报告.md` 查找 → 得到 blob 的 SHA |
| **③ 写入** | 从 `.git/objects/` 读取 blob（zlib 压缩），解压后**同时写入 Index 和 Working Directory** |
| **④ HEAD 不动** | HEAD 依然指向原来的分支（如 master），不随 `<commit>` 改变 |

---

## 四、Git 对象存储模型

Git 本质是一个**内容寻址的键值数据库**。核心有四种对象：

```
┌─────────────────────────────────────────────────────┐
│              Git 对象模型 (Object Model)              │
├──────────┬──────────────────────────────────────────┤
│ 对象类型  │ 含义                                       │
├──────────┼──────────────────────────────────────────┤
│ blob     │ 文件内容本身（不含文件名、路径）                │
│ tree     │ 目录结构快照，指向 blob 和子树 tree            │
│ commit   │ 一次提交的元数据 + 指向 tree + parent commit  │
│ tag      │ 带注释的标签，指向 commit                     │
└──────────┴──────────────────────────────────────────┘
```

### 一个 commit 的内部结构

```
Commit: 9915aee ("同步用")
├─ tree: a1b2c3d4...           ← 根目录快照
├─ parent: e5f6g7h8...         ← 上一个 commit
├─ author: 29344
└─ committer: 29344

Tree a1b2c3d4 (根目录):
├─ Blob 789abc00 → "main.c"         的内容
├─ Blob def01234 → "README.md"      的内容
├─ Tree 55566677 → "docs/"          子目录
│     └─ Blob aaaabbbb → "docs/报告.md" 的内容  ← 我们的目标文件
└─ Tree 888999aa → "tools/"         子目录
```

> 💡 **关键洞察**：`git checkout <commit> -- <file>` 本质上就是：
> 1. 沿着 commit → tree → (可能有多层 sub-tree) → blob 的链条找文件
> 2. 把 blob 解压，写入暂存区和磁盘
> 3. 不动 commit 和 HEAD 那条线

---

## 五、与其他命令的对比

| 命令 | HEAD | Index | Working Dir | 用途 |
|------|------|-------|-------------|------|
| `git checkout master` | ✅ 更新 | ✅ 更新 | ✅ 更新 | 切换分支 |
| `git checkout 9915aee` | ✅ 更新 | ✅ 更新 | ✅ 更新 | 进入游离分支 |
| **`git checkout 9915aee -- file`** | ❌ 不动 | ✅ 只改此文件 | ✅ 只改此文件 | **精准搬运** |
| `git restore --source=9915aee file` | ❌ 不动 | ✅ 只改此文件 | ✅ 只改此文件 | 新版等价命令 |
| `git cherry-pick 9915aee` | ✅ 新建 commit | ✅ 更新全部 | ✅ 更新全部 | 搬整个 commit |
| `git stash` | ❌ 不动 | ❌ 不动 | 保存未提交修改 | 暂存脏工作区 |

> ℹ️ Git 2.23+ 引入了 `git restore` 作为 `git checkout` 功能拆分后的替代命令：
> ```bash
> # 等价于 git checkout 9915aee -- file
> git restore --source=9915aee --staged --worktree file
> ```

---

## 六、实际使用场景

### 场景 1：从游离分支捞文件（本文场景）
```bash
# HEAD 游离在某个 commit，想搬文件到 master
git checkout master
git checkout <detached-commit> -- "path/to/file"
git commit -m "从历史中恢复 xxx 文件"
```

### 场景 2：恢复某个文件到历史版本
```bash
# 文件改坏了，想回到昨天的版本
git log --oneline -- path/to/file    # 找到历史 commit
git checkout a1b2c3d -- path/to/file # 恢复
```

### 场景 3：从别的分支拿一个文件
```bash
git checkout feature-branch -- src/utils.ts
```

---

## 七、关键要点总结

> 🎯 **核心认知**：`git checkout <commit> -- <file>` = 伸手去历史的箱子里掏一个文件，人不动。

1. **它更新 Index + Working Directory，但不动 HEAD**
2. 文件会被直接放到暂存区（相当于自动 `git add`），不需要再 `git add`
3. Git 底层通过 commit → tree → blob 的对象链条定位文件内容
4. Git 2.23+ 推荐用 `git restore --source=<commit> <file>` 替代此命令
5. 如果 `<commit>` 里没有这个文件，命令会报错（不会悄悄忽略）

---

*整理日期：2026-05-06*
