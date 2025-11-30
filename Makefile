.PHONY: clean

# 清理 temp 文件夹内的所有文件，但保留文件夹结构
clean:
	@powershell -Command "if (Test-Path temp) { Get-ChildItem -Path temp -Recurse -File | Remove-Item -Force; Write-Host '已清理 temp 文件夹内的所有文件' } else { Write-Host 'temp 文件夹不存在' }"

