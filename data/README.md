# data/

这里放由本机已安装（授权）库提取出来的数据库，例如：

- `vsl-patches.csv` —— 全部 patch（约 2.5 万条）
- `vsl-presets.csv` —— 工厂预设名
- `vsl-patches-by-collection.csv`
- `vsl-content-ids.txt` / `vsl-instrument-ids.*`
- `cache/` —— 每卷缓存

**这些内容不入库**（`.gitignore` 已忽略）：它们是可再生成的、且与本机环境相关。
一条命令即可重建：

```powershell
powershell -ExecutionPolicy Bypass -File ..\scripts\build-vsl-patch-db.ps1 -LibraryRoot "<your VSL library root>"
```

全量重建约 95 秒；之后增量刷新只要几秒（未变动的卷按 大小+mtime 跳过）。
