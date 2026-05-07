# Git Detached HEAD 问题分析与修复

## 问题描述
在 `probe-rs-src` 子仓库中，执行 `git commit` 后，提交落在了 **detached HEAD（游离头）** 状态，而不是 `master` 分支上。尝试 `git push` 失败，切换回 `master` 分支时该提交被"遗留"了。

## 问题分析

### 什么是 Detached HEAD？
- **HEAD** 是 Git 中指向当前所在位置的指针。
- 正常情况下，HEAD 指向一个**分支**（如 `master`），当你提交时，分支指针会跟着前进。
- 当 HEAD 直接指向某个**具体的 commit**（而不是分支名）时，就进入了"游离头"状态。

### 为什么会进入游离头状态？
常见原因：
1. **`git checkout <commit-hash>`** — 直接 checkout 到某个 commit
2. **`git checkout <tag>`** — checkout 到某个 tag
3. 在这里，你应该是从某个 tag 或 commit（`cb0d151d`）checkout 过来的：

```
* (HEAD detached from cb0d151d)
```

也就是说，你当前的 HEAD 是直接指向 commit `cb0d151d`，而不是 `master` 分支。所以你后来做的修改和提交都"挂"在了这个游离头上，并没有连接到任何分支。

### 技术细节
```
游离头状态下的提交链：
  cb0d151d  <-- origin/master, master
      |
  322873c7  <-- HEAD (detached, 你刚做的提交)
```

`master` 和 `origin/master` 还在 `cb0d151d`，而你新做的提交 `322873c7` 只存在于游离头上，不属于任何分支。一旦你 checkout 到 `master`，这个提交就成了"孤儿"，Git 会警告你：

```
Warning: you are leaving 1 commit behind, not connected to
any of your branches:
  322873c7 ...
```

不过不用担心！这个提交**没有被删除**，它还在 Git 的对象数据库中，可以通过 commit hash 找回来。

## 解决方案

### 方案一：从现有 commit hash 创建分支（推荐，最简单）

```bash
# 基于那个游离提交创建一个新分支
git branch fix/cyt2bl-flash-support 322873c7

# 切换到 master
git checkout master

# 合并这个分支
git merge fix/cyt2bl-flash-support

# 推送到远程
git push origin master
```

### 方案二：使用 cherry-pick

```bash
# 在 master 分支上 cherry-pick 那个提交
git cherry-pick 322873c7

# 推送到远程
git push origin master
```

### 支持这种操作的技术细节
- `git branch <name> <commit-hash>` 可以在任意 commit 上创建分支
- `git cherry-pick <commit-hash>` 可以把任意 commit 的改动应用到当前分支
- Git reflog 会保留所有 HEAD 移动的历史（包括游离头），即使不用 commit hash 也能找回

## 总结
- 游离头状态下做的提交，只属于 HEAD 不属于任何分支
- 切换到分支后，游离头上的提交会成为"孤儿"，但不会被删除
- 用 `git branch <name> <commit-hash>` 或 `git cherry-pick` 可以轻松救回
