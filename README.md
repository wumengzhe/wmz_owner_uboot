# wmz_owner_uboot

独立的 GitHub Actions CI，用于基于 [wumengzhe/bl-mt798x-dhcpd](https://github.com/wumengzhe/bl-mt798x-dhcpd)
的 **`wmz-uboot` 分支** 构建 MT7981 / MT7986 的 ATF(BL2) + U-Boot(FIP)。

> 本仓库**只存放 CI 工作流**，源码仍在 `bl-mt798x-dhcpd`——不在源码仓库内建工作流
> （模仿 [UBOOT-CI](https://github.com/wumengzhe/UBOOT-CI) 的做法）。

## 为什么单独建仓库

UBOOT-CI 的 `cleanup` 任务会清空**全部** Release 与 Workflow 记录（`releases_keep_latest: 0`），
若共用同一仓库会互相删除对方的产物，因此 wmz-uboot 版本单独建仓。

## 用法

手动触发：`Actions` → `798x-UBOOT-wmz` → `Run workflow`

| 输入 | 说明 | 默认 |
|---|---|---|
| `version` | ATF/U-Boot 版本：`2025` / `SP1` / `SP2` | `2025` |
| `variant` | `default`(标准 BL2+fip) / `ubootmod`(.itb 布局) / `ubi` / `nonmbm` / `openwrt` / `auto` | `default` |
| `boards` | 只构建指定机型（逗号分隔，**不含 soc 前缀**）。留空=构建全部 | 空 |

### 示例：只给 N60 PRO 编译适配 `.itb` 的固件引导器

- version: `2025`
- variant: `ubootmod`
- boards: `netcore_n60-pro`

## 构建范围

扫描 `uboot-mtk-20250711/configs*` 下全部 `mt7981_*` / `mt7986_*` defconfig，
剔除 `rfb` / `fpga` 参考板并去重，当前共 **95 台机型**（MT7981 66 + MT7986 29），
按每 8 台一组切块并行构建（约 12 个并行任务），避免单任务超时。

`variant` 留 `auto` 时，会为每台机型自动挑选存在的配置目录
（优先级 `configs` → `configs-fit` → `configs-ubi` → `configs-nonmbm` → `configs-openwrt`）。

## 产物

- 每个分块上传 artifact：`mt798x-uboot-chunk-N`（保留 30 天）
- 全部汇总打包为一个 Release zip：`mt798x-uboot-<ver>-<variant>-<date>.zip`
  - `bl2-*.img`：BL2 preloader
  - `fip-*.bin`：U-Boot FIP

## 说明

- `wmz-uboot` 分支已包含 **W25N04KV（512MB SPI-NAND）** 支持补丁，
  构建产物可直接用于更换 512M 闪存的设备（如磊科 N60 PRO）。
- 构建时传入 `SILENT=Y`，避免 `build.sh` 在 CI 中因交互提示卡死。
- **BL2 不区分闪存容量**（只做 DDR 初始化 + 加载 FIP），无需为 512M 单独编译 BL2；
  NAND 容量由 U-Boot/内核 DTS 的 `ubi` 分区"撑满"写法在运行时自动适配。
- 刷机前请务必备份并保留 **Factory 校准分区**（含 WiFi 校准数据与 MAC）。
