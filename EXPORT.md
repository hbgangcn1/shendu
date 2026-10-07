# 蜃都 — 导出指南

## 前置条件

1. 安装 Godot 4.6.3
2. 下载 Windows 导出模板：
   - 打开 Godot → 编辑 → 管理导出模板 → 下载
   - 或手动下载：https://godotengine.org/download

## 导出步骤

### 方法 1：使用 Godot 编辑器

1. 打开项目：`项目` → `打开项目` → 选择 `shendu/`
2. 导出：`项目` → `导出...`
3. 选择 `Windows Desktop` 预设
4. 点击 `导出项目`
5. 保存到 `build/shendu.exe`

### 方法 2：命令行导出

```bash
# 确保 Godot 在 PATH 中
godot --headless --export-release "Windows Desktop" build/shendu.exe
```

### 方法 3：PowerShell 脚本

```powershell
# 在项目根目录运行
$godotPath = "C:\path\to\godot.exe"  # 修改为实际路径
& $godotPath --headless --export-release "Windows Desktop" "build/shendu.exe"
```

## 输出目录结构

```
shendu/
├── build/
│   └── shendu.exe    ← 导出的可执行文件
└── ...
```

## 测试导出

1. 运行 `build/shendu.exe`
2. 验证：
   - 主菜单显示正常
   - 点击"开始演示"进入战斗
   - 战斗流程可正常进行
   - 结束回合按钮工作
   - 卡牌可正常打出

## 已知问题

- 首次运行可能需要关闭 Windows Defender 实时保护（误报）
- 导出后字体可能需要重新加载

## 下一步

- [ ] 添加游戏图标
- [ ] 添加启动画面
- [ ] 压缩 PCK 文件
- [ ] 代码签名（可选）
