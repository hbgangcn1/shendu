# 蜃都 (Shendu) - 智能代理开发规范

## 项目概述

**蜃都**是一款基于 Godot 4.6 的卡牌构建 Roguelike 游戏（类 Slay the Spire），融合都市修仙与五行系统。AI 代理在此项目中负责代码开发、测试、审查和维护。

## 核心规则

### 1. 代码质量红线

**不允许出现以下情况：**
- ❌ 任何测试失败、错误、警告或跳过
- ❌ 类型注解覆盖率低于 95%
- ❌ 安全漏洞（路径遍历、未验证输入、硬编码凭证）
- ❌ 内存泄漏（未断开的信号、未释放的节点）
- ❌ 空指针访问或数组越界
- ❌ 魔法数字（必须使用具名常量）

### 2. 检查-修复循环（强制）

**每次写完代码后，必须执行：**

```
1. 运行所有测试（零失败、零跳过）
2. 代码审查（检查安全、内存、性能）
3. 检查 Linter（零警告）
4. 如果有问题 → 修复 → 重新检查
5. 重复直到再也发现不了问题
```

**禁止行为：**
- 跳过失败测试
- 使用 `@ts-ignore` 或类型抑制
- 忽略 Linter 警告
- 将问题留到"下次修复"

### 3. 测试要求

**覆盖率要求：**
- 核心逻辑（五行计算、伤害公式）：100% 覆盖
- 战斗系统（Actor、Player、Enemy、BattleManager）：90% 覆盖
- UI 系统：70% 覆盖（关键交互路径）

**测试边界必须覆盖：**
- 正常流程（Happy Path）
- 边界条件（空数组、零值、最大值）
- 错误条件（无效输入、异常状态）
- 并发/时序问题（信号顺序、异步操作）

**测试文件命名：**
```
test_<module>.gd          # 单元测试
test_<feature>_integration.gd  # 集成测试
```

### 4. 代码风格

**GDScript 规范：**
- 类名：PascalCase
- 函数/变量：snake_case
- 常量：CONSTANT_CASE
- 私有成员：前缀 `_`
- 信号：snake_case

**文件结构顺序：**
```gdscript
1. @tool / @icon / class_name
2. 信号 (signal)
3. @export 变量
4. @onready 变量
5. 其他类变量
6. 生命周期回调 (_ready, _process)
7. 公共方法
8. 私有方法
```

**类型注解（强制）：**
```gdscript
# ✅ 正确
var health: int = 100
var enemies: Array[Enemy] = []
func take_damage(amount: int, element: WuXing.Element) -> int:

# ❌ 错误
var health = 100
var enemies = []
func take_damage(amount, element):
```

### 5. 安全规范

**输入验证：**
- 所有文件路径必须验证在允许范围内
- JSON/外部数据必须验证结构后再使用
- 动态加载资源前检查存在性

**信号管理：**
- 连接信号必须检查是否已连接
- 节点销毁前必须断开所有信号
- 使用 `_exit_tree()` 清理资源

**内存管理：**
- 使用 `queue_free()` 而非 `free()`
- Tween 动画必须存储引用或确保完成
- 动态创建的节点必须记录引用以便清理

### 6. 性能规范

**禁止：**
- 在 `_process` 中进行物理计算
- 每帧遍历场景树
- 每帧字符串拼接
- 频繁数组复制

**推荐：**
- 缓存节点引用（`@onready`）
- 使用 `distance_squared_to` 替代 `distance_to`
- 对象池模式复用节点
- 可见性剔除（`set_process(false)`）

### 7. 架构原则

**设计模式：**
- Autoload 单例：仅用于真正的全局状态（WuXing、EventBus）
- 状态机：复杂流程使用显式状态机
- 信号解耦：模块间通过 EventBus 通信
- 资源模式：数据类继承 Resource，而非 Node

**文件组织：**
```
scripts/
├── core/          # 核心系统（Autoload）
├── battle/        # 战斗逻辑
├── ui/            # UI 组件
└── test/          # 测试文件
```

### 8. 提交规范

**提交信息格式：**
```
<type>(<scope>): <subject>

<body>

<footer>
```

**类型：**
- `feat`: 新功能
- `fix`: 修复
- `test`: 测试
- `refactor`: 重构
- `docs`: 文档
- `style`: 代码风格

**示例：**
```
fix(battle): 修复 discard_pile 为空时的崩溃

test(五行): 添加相克边界测试
```

## 工作流程

### 1. 任务开始前
- 阅读相关代码文件
- 理解现有架构和模式
- 确认测试覆盖范围

### 2. 编码阶段
- 先写测试，再写实现（TDD）
- 保持类型注解完整
- 添加必要注释

### 3. 验证阶段
- 运行所有测试
- 检查 Linter
- 手动审查代码
- 修复 → 重新检查（循环）

### 4. 完成阶段
- 确认零错误、零警告、零跳过
- 更新相关文档
- 提交代码

## 工具配置

### Linter (gdtoolkit)
```bash
pip install "gdtoolkit==4.*"
gdlint scripts/
gdformat --check scripts/
```

### 测试运行
```bash
# 内置测试
F6 或在 Godot 编辑器中运行场景

# 命令行（需安装 GUT）
godot --headless -s res://addons/gut/gut_cmdln.gd -gdir=res://scripts/test
```

### CI/CD 检查清单
- [ ] 所有测试通过
- [ ] Linter 无警告
- [ ] 类型检查通过
- [ ] 无安全漏洞
- [ ] 无内存泄漏风险

## 常见陷阱

1. **Actor 继承 Node2D**：Actor 是纯数据类，不应继承 Node。应改为独立类或使用 Resource。
2. **信号未断开**：BattleManager 等类在销毁前必须断开 player/enemy 的信号。
3. **Tween 泄漏**：创建 Tween 后未存储引用，可能导致动画异常。
4. **数组越界**：访问 `discard_pile.back()` 前未检查是否为空。
5. **硬编码路径**：资源路径应使用常量或配置。

## 参考文档

- [Godot 4 GDScript 风格指南](https://docs.godotengine.org/en/stable/tutorials/scripting/gdscript/gdscript_styleguide.html)
- [Godot 性能优化](https://docs.godotengine.org/en/stable/tutorials/performance/)
- [GUT 测试框架文档](https://gut.readthedocs.io/)

---

**最后更新：** 2026-05-24
**版本：** v1.0
