# R Homework PDF Service

把 R 作业脚本一键转换成排版清晰的 PDF。适合老师要求保留完整代码、注释、运行结果和图像的 R 课程作业。

这个工具不会修改原始 `.r` 文件。它会读取脚本内容，自动生成同名 `.Rmd`，再渲染出 PDF。

本项目受到数据分析基础课程启发，可以辅助快速排版渲染。

## 功能

- 保留原始 R 代码、注释、空行和运行输出
- 自动识别题号注释，例如 `#P192  7.2`、`#P193   7.6`、`#P254，10.1`
- 每道题独立成节，PDF 中自动显示目录和代码块
- 支持 R 作图，图像会进入 PDF
- 提供两种使用方式：拖拽单个文件，或启动投递箱服务批量处理
- 优先使用项目内 TinyTeX，也会尝试系统里的 XeLaTeX

## 准备

请先安装：

- R
- RStudio 或 Pandoc
- 可用的 LaTeX 环境。推荐 TinyTeX 或已加入 PATH 的 XeLaTeX

如果你已经有项目内 `.TinyTeX`，可以把它放在本工具目录下；工具会优先使用它。没有项目内 `.TinyTeX` 时，工具会尝试使用系统 PATH 中的 `xelatex`。

## 最简单用法：拖拽转换

1. 把这个仓库下载到电脑。
2. 把写好的 `.r` 作业文件拖到 `convert_r_to_pdf.bat` 上。
3. 等待窗口运行结束。
4. 在 `pdf_output` 文件夹里查看生成的 PDF。

也可以在 PowerShell 中运行：

```powershell
.\convert_r_to_pdf.bat "path\to\homework.r"
```

## 批量投递箱模式

双击：

```text
start_r_pdf_service.bat
```

窗口会显示两个文件夹：

```text
inbox       放入 .r 文件
pdf_output 生成 PDF 的位置
```

启动后，把 `.r` 文件放进 `inbox`，工具会自动处理并把 PDF 放进 `pdf_output`。关闭窗口即可停止服务。

## 推荐的 R 作业写法

题号建议写成独立注释行：

```r
#P192  7.2

#（1）
x <- c(1, 2, 3)
mean(x)

#P193  7.6

y <- c(2, 4, 6)
cor(x, y)
```

小题注释、普通注释和代码都会原样保留在代码块中。

## 输出文件

转换后通常会得到：

```text
homework.Rmd
homework.pdf
homework_files\
```

服务模式下，最终 PDF 会复制到：

```text
pdf_output\
```

临时工作目录、日志、PDF 和生成图像都已加入 `.gitignore`，不会被提交到仓库。

## 提醒

- 为保障隐私，建议只在本地处理真实作业。
- 公开仓库只放工具和脱敏示例，不放真实作业、日志和生成 PDF。

## 排错

常见问题见 [docs/troubleshooting.md](docs/troubleshooting.md)。

## License

MIT License
