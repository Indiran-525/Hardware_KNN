
# Hardware Accelerated KNN on FPGA (ZedBoard)

![Platform](https://img.shields.io/badge/Platform-ZedBoard%20(Zynq--7000)-blue)
![Language](https://img.shields.io/badge/Language-Verilog-orange)
![Architecture](https://img.shields.io/badge/Architecture-Single--Cycle%20Streaming-blueviolet)

This repository contains the RTL implementation of a **K-Nearest Neighbors (KNN)** hardware accelerator for the **Avnet ZedBoard**. The design features a high-performance **single-cycle streaming datapath** that processes one training point every clock cycle, achieving near-zero latency overhead for Edge AI classification.

## 🎯 Objective
To design a hardware IP for the K-Nearest Neighbors algorithm that maximizes throughput by processing data points in a continuous stream. The system targets **near real-time inference** by eliminating pipeline stalls and software overhead.

## 📖 Overview
KNN is a lazy learning algorithm that classifies input based on the majority vote of its nearest neighbors. This hardware implementation is optimized for **low-latency execution**:
* **Dynamic K-Factor:** Switchable between **K=3** and **K=5** at runtime via Switch 0.
* **Single-Cycle Datapath:** Performs memory fetch, Euclidean distance calculation, and sorting comparison in a single clock cycle per point.
* **Deterministic Timing:** Guaranteed execution time of **N+2 cycles** for N data points (66 cycles total for 64 points).

## ⚙️ Architecture & Workflow

The design utilizes a **Streaming Iterative Architecture** rather than a deep pipeline. This ensures that the moment the last data point is read, the classification result is ready immediately.



1.  **Address Generator:**
    * Counters drive the ROM address to stream 64 training points sequentially.
2.  **Combinational Distance Engine:**
    * **Input:** Coordinates $(X, Y)$ from ROM and Input Vector.
    * **Logic:** Computes Squared Euclidean Distance ($dx^2 + dy^2$) purely in combinational logic using DSP48 slices.
    * **Speed:** Entire calculation completes within the 8ns clock period.
3.  **Systolic Sorter (Best K Block):**
    * Receives the calculated distance in the same cycle.
    * Compares the new distance against the currently stored "Top K" candidates.
    * **Update:** If the new point is closer, the register array updates at the next clock edge.
4.  **Majority Voter:**
    * Once the stream finishes, combinational logic instantly resolves the majority class from the Top K registers.

## 📊 Performance Benchmark

| Metric | Value | Notes |
| :--- | :--- | :--- |
| **Clock Frequency** | 100 MHz | (Period: 10.00 ns) |
| **Throughput** | 1 Point / Cycle | Streaming Processing |
| **Total Latency** | **34 Cycles** | ~340 ns total execution time |
| **Critical Path** | ROM $\to$ Dist $\to$ Sort | Fits within 8ns (Positive Slack) |

*By executing the entire `Fetch -> Calc -> Sort` chain in a single cycle, the design minimizes register overhead and latency.*

## 🛠️ Tools & Hardware
* **Hardware:** ZedBoard (Xilinx Zynq-7000 SoC - XC7Z020)
* **EDA Tool:** Xilinx Vivado Design Suite
* **Language:** Verilog HDL
* **Key IO:**
    * **SW0:** Mode Select (0 = K3, 1 = K5)
    * **BTN:** Reset
    * **LEDs:** Output Class & Done Flag

│   └── zedboard.xdc           # Physical constraints
└── docs/
