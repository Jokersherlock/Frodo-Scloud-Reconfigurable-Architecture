## Frodo-Scloud

本仓库包含三部分：

- `spinal/`：SpinalHDL（Scala）源码与生成 Verilog 的工程
- `rtl/`：生成/存放 Verilog（本工程生成目录为 `rtl/generated/`）
- `sim/`：仿真（本工程 cocotb 位于 `sim/cocotb/`）

---

## 1. SpinalHDL：在 `spinal/` 内如何创建文件

### 1.1 目录约定（本工程）

- **Scala 源码根目录**：`spinal/src/`
  - `spinal/build.sbt` 已设置 `Compile / scalaSource := baseDirectory.value / "src"`，因此源码直接放在 `spinal/src/**.scala`
- **生成 Verilog 输出目录**：`rtl/generated/<subdir>/`
  - `spinal/src/common/GenConfig.scala` 固定配置：
    - `targetDirectory = "../rtl/generated/<subdir>"`

### 1.2 新增一个模块（示例）

1. 在合适的包路径下新建 Scala 文件，例如：
   - `spinal/src/mem/acc/Foo.scala`
2. 在文件中定义模块（`Component`）与 IO（`Bundle`）
3. 提供一个可运行的生成入口（带 `main` 的 object），用于导出 `.v`

工程已有参考：

- `spinal/src/mem/acc/AccSlice.scala` 中的 `object GenAccSlice`

---

## 2. 生成 `.v`（Verilog）

本工程的生成方式是运行某个带 `main` 的 Scala object，由 SpinalHDL 导出 Verilog。

以生成 `AccSlice` 为例（在仓库根目录执行）：

```bash
cd spinal
```

建议先显式指定 sbt/coursier 缓存目录到当前工程内，避免某些环境写入 `~/.sbt` 或 `/root/.sbt` 时的权限问题：

```bash
export SBT_USER_HOME="$(pwd)/.sbt"
export COURSIER_CACHE="$(pwd)/.cache/coursier"
```

运行生成入口：

```bash
sbt "runMain mem.acc.GenAccSlice"
```

生成结果输出到：

- `rtl/generated/mem/acc/AccSlice.v`

---

## 3. `sim/` 下使用 cocotb 仿真（`sim/cocotb/`）

### 3.1 目录说明

- `sim/cocotb/Makefile`：cocotb 仿真入口
- `sim/cocotb/tests/`：Python 测试用例目录
  - 现有用例：`sim/cocotb/tests/tb_acc_slice.py`

Makefile 默认配置：

- `SIM ?= verilator`
- `TOPLEVEL ?= AccSlice`
- `MODULE ?= tb_acc_slice`
- Verilog 源文件来自 `rtl/`（Makefile 当前会把 `rtl/` 下所有 `.v` 加入编译）

### 3.2 推荐仿真流程（一键跑通）

先生成/更新 Verilog：

```bash
cd spinal
export SBT_USER_HOME="$(pwd)/.sbt"
export COURSIER_CACHE="$(pwd)/.cache/coursier"
sbt "runMain mem.acc.GenAccSlice"
cd ..
```

再运行 cocotb：

```bash
cd sim/cocotb
make
```

### 3.3 常用命令

打印 Makefile 实际使用的变量（便于排查）：

```bash
cd sim/cocotb
make print-vars
```

切换测试用例（例如新增 `tests/tb_xxx.py`）：

```bash
cd sim/cocotb
make MODULE=tb_xxx
```

切换顶层模块：

```bash
cd sim/cocotb
make TOPLEVEL=YourTop MODULE=tb_your_top
```

清理仿真产物：

```bash
cd sim/cocotb
make clean-local
```

