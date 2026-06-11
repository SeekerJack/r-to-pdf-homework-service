# Troubleshooting

## PowerShell 提示不能运行脚本

优先使用 `.bat` 文件启动工具。如果你需要直接运行 PowerShell 脚本，可以使用：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\start_r_pdf_service.ps1
```

## 找不到 Rscript

请确认 R 已安装，并且 `Rscript.exe` 可用。工具会先尝试常见安装路径，再尝试系统 PATH。

如果你的 R 安装在其他位置，可以把 R 的 `bin` 目录加入 PATH，或在脚本中调整 `Get-RscriptPath` 的默认路径。

## PDF 没有生成

先查看 `service_logs` 中最新的日志文件。常见原因包括：

- R 代码本身运行报错
- 缺少 R 包
- 缺少 LaTeX 包
- 文件名或路径中包含特殊字符

工具不会修改你的 R 作业内容；如果原脚本运行失败，PDF 渲染也会失败。

## 图像没有进入 PDF

请确认作图代码在 R Markdown 中实际执行。通常直接调用 `plot()`、`ggplot()` 或打印图像对象即可。

如果图像对象只被赋值但没有打印，可以在原始 `.r` 文件中自行决定是否添加打印语句。工具不会自动改写作业代码。

## 中文乱码

建议使用 UTF-8 保存 `.r` 文件。PDF 渲染使用 XeLaTeX，并尽量选择中文友好的设置。

如果仍然乱码，请检查：

- 原始 `.r` 文件编码
- 系统是否有中文字体
- LaTeX 是否可正常编译中文文档

可以在发布目录运行关键词搜索，确认没有敏感内容后再提交。
