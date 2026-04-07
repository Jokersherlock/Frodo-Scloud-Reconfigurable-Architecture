# ============================================================
# Basic simulator selection
# ------------------------------------------------------------
# 默认使用 iverilog。
# 如果以后想切到 verilator，可以在命令行覆盖：
#   make SIM=verilator
# ============================================================
SIM ?= verilator


# ============================================================
# Python test configuration
# ------------------------------------------------------------
# MODULE 是 cocotb 要加载的 Python 测试文件名（不带 .py）
# 当前对应 tests/test_accslice.py
#
# 如果以后你新增 test_xxx.py，只需要改这里：
#   make MODULE=test_xxx
# ============================================================
MODULE ?= tb_acc_slice


# ============================================================
# HDL top-level configuration
# ------------------------------------------------------------
# TOPLEVEL 是 Verilog 顶层模块名
# TOPLEVEL_LANG 一般就是 verilog
#
# 如果以后你要测别的顶层，比如 PseudoDpram：
#   make TOPLEVEL=PseudoDpram MODULE=test_pseudodpram
# ============================================================
TOPLEVEL ?= AccSlice
TOPLEVEL_LANG ?= verilog


# ============================================================
# Directory configuration
# ------------------------------------------------------------
# 当前 Makefile 位于 sim/cocotb/
# 因此：
#   工程根目录      = ../..
#   RTL 生成目录     = ../../rtl/generated/mem/acc
#   测试文件目录     = ./tests
#
# 这样写的好处是：
#   目录关系清晰
#   后续如果 AccSlice 的 RTL 还在同一目录下，基本不用改
# ============================================================
ROOT_DIR    := ../..
RTL_DIR     ?= $(ROOT_DIR)/rtl
TEST_DIR    ?= $(CURDIR)/tests


# ============================================================
# Python import path
# ------------------------------------------------------------
# 让 cocotb 能找到 tests/ 目录下的 Python 文件
# 如果你以后把一些公共 helper 拆到别的目录，也可以继续往后加
# ============================================================
PYTHONPATH := $(TEST_DIR):$(PYTHONPATH)
export PYTHONPATH


# ============================================================
# Verilog source list
# ------------------------------------------------------------
# 这里是最关键的部分：
# cocotb 需要知道仿真要编哪些 Verilog 文件
#
# 当前先手工列出 AccSlice 所需文件。
# 这种写法最稳，因为：
#   1. 不会把目录里无关的 .v 一股脑加进来
#   2. 顶层依赖关系更清楚
#
# 如果以后依赖模块变多，就继续在这里加。
# ============================================================
# VERILOG_SOURCES = \
# 	$(RTL_DIR)/AccSlice.v \

VERILOG_SOURCES =  $(sort $(shell find $(RTL_DIR) -type f -name "*.v"))

INC_DIRS := \
	$(RTL_DIR) \

COMPILE_ARGS = $(addprefix -I,$(INC_DIRS))

# ============================================================
# Optional waveform control
# ------------------------------------------------------------
# 默认打开波形，便于调试。
# 如果你不想生成波形，可运行：
#   make WAVES=0
#
# 不同 simulator 对波形支持略有差异，但 cocotb 通常能处理。
# ============================================================
WAVES ?= 1
export WAVES


# ============================================================
# Optional plusargs / extra arguments
# ------------------------------------------------------------
# 如果以后你想给 simulator 传额外参数，可以直接在命令行覆盖：
#   make EXTRA_ARGS="-Wall"
# 或者：
#   make PLUSARGS="+seed=123"
# ============================================================
EXTRA_ARGS ?=
PLUSARGS   ?=

export EXTRA_ARGS
export PLUSARGS


# ============================================================
# Regression seed / reproducibility
# ------------------------------------------------------------
# 如果以后 Python 测试里想读取环境变量控制随机种子，
# 可以从这里统一传进去：
#   make RANDOM_SEED=123
# ============================================================
RANDOM_SEED ?= 42
export RANDOM_SEED


# ============================================================
# Cocotb makefile include
# ------------------------------------------------------------
# 这是标准 cocotb 用法
# ============================================================
include $(shell cocotb-config --makefiles)/Makefile.sim


# ============================================================
# Convenience targets
# ------------------------------------------------------------
# 下面这些 target 不是必须，但很好用
# ============================================================

# 打印当前配置，便于确认 make 实际使用了哪些参数
print-vars:
	@echo "SIM=$(SIM)"
	@echo "MODULE=$(MODULE)"
	@echo "TOPLEVEL=$(TOPLEVEL)"
	@echo "TOPLEVEL_LANG=$(TOPLEVEL_LANG)"
	@echo "ROOT_DIR=$(ROOT_DIR)"
	@echo "RTL_DIR=$(RTL_DIR)"
	@echo "TEST_DIR=$(TEST_DIR)"
	@echo "VERILOG_SOURCES=$(VERILOG_SOURCES)"
	@echo "WAVES=$(WAVES)"
	@echo "RANDOM_SEED=$(RANDOM_SEED)"
	@echo "EXTRA_ARGS=$(EXTRA_ARGS)"
	@echo "PLUSARGS=$(PLUSARGS)"

# 清理常见仿真输出
# cocotb 自己也会生成 sim_build 等目录，这里一起删掉
clean-local:
	rm -rf sim_build
	rm -f results.xml
	rm -f *.vcd
	rm -f *.fst
	rm -f *.xml

# 完整清理
clean-all: clean-local