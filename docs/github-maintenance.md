# GitHub Maintenance Guide

这份说明写给第一次维护 GitHub 仓库的人。照着做就可以，不需要先学完整 Git。

## 1. 怎么看自己的仓库

仓库地址：

```text
https://github.com/SeekerJack/r-to-pdf-homework-service
```

打开页面后，重点看这几个地方：

- `README.md`：别人点进仓库后最先看到的说明。
- `Code` 文件列表：仓库里公开发布了哪些文件。
- `Commits`：每次修改和上传的记录。
- `docs/`：放更详细的说明。
- `examples/`：放脱敏示例，不放真实作业。

## 2. 以后怎么更新

所有修改都在你自己的发布目录里做，也就是包含 `README.md`、`.gitignore` 和这些脚本的文件夹。

推荐流程：

```powershell
git status
git add .
git commit -m "Update documentation"
git push
```

如果当前 PowerShell 不认识 `git`，可以使用 Git 的完整路径：

```powershell
& "C:\Program Files\Git\cmd\git.exe" status
```

## 3. 上传前必须检查什么

公开仓库不要上传这些内容：

- 真实作业文件
- 真实作业 PDF
- 运行日志
- `.TinyTeX`
- `.r-lib`
- `.service-work`
- `pdf_output`
- `inbox`
- 本机路径、姓名、学号、班级等个人信息

提交前先看：

```powershell
git status --short --ignored
```

正常情况下，日志、PDF 输出和临时目录应该显示为被忽略，不应该出现在待提交列表里。

## 4. 隐私自查

每次准备发布前，在发布目录里搜索敏感词。可以把下面的关键词换成自己的真实信息：

```powershell
Select-String -Path .\* -Pattern "姓名","学号","用户目录","真实作业名" -SimpleMatch
```

如果有命中，先确认它是不是公开安全内容。真实个人信息不要提交。

## 5. 常见维护动作

改 README：

```powershell
notepad README.md
git status
git add README.md
git commit -m "Improve README"
git push
```

新增示例：

```powershell
copy your-safe-example.r examples\
git status
git add examples\
git commit -m "Add safe example"
git push
```

查看最近一次提交：

```powershell
git log --oneline -1
```

## 6. 出问题时先做什么

先不要删除文件。先运行：

```powershell
git status --short --ignored
```

如果看到不该上传的文件在待提交列表里，先不要 `git add .`，也不要 `git commit`。把文件移出发布目录，或确认 `.gitignore` 是否需要补充规则。

如果只是运行工具产生了 PDF、日志、临时目录，这些通常已经被 `.gitignore` 忽略，不需要处理。
