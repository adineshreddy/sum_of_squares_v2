# Project 1: Sums of Consecutive Squares

**Distributed Operating Systems Principles - Fall 2025**

## Group Info:
- Dinesh Reddy Ande - 58723541
- Saaketh Balachendil - 86294284

## Problem Definition

This project explores a fascinating mathematical problem: finding instances where the sum of the squares of consecutive integers equals a perfect square. For example, the well-known Pythagorean theorem shows that 3² + 4² = 5². Another remarkable case is the sum of the squares from 1 to 24, which equals 70² (1² + 2² + ... + 24² = 70²).

The objective of this project is to develop an efficient, multi-core solution to this problem using the Gleam programming language and the actor model.

Given two parameters:
- **N**: The upper bound for starting positions (search range: 1 to N)
- **k**: The length of consecutive integer sequences to examine

The program finds all starting positions `i` where: `i² + (i+1)² + (i+2)² + ... + (i+k-1)² = perfect square`

## Implementation

Our solution leverages Gleam's actor model to create a distributed, parallel computation system:

- **Actor-Based Architecture**: The program uses a boss-worker pattern with one coordinator (boss) actor and multiple worker actors. The boss distributes work ranges among workers and collects results, while workers process their assigned ranges independently and report back findings.

- **Dynamic Work Distribution**: Work is divided into chunks using the formula `work_unit_size = max(100, N/50)`, creating approximately 50 work units distributed among 8 parallel workers. This approach ensures balanced load distribution while minimizing coordination overhead.

- **Optimized Mathematical Operations**: Each worker efficiently computes consecutive square sums using the formula for arithmetic progression of squares, and validates perfect squares using Gleam's built-in integer square root with floating-point verification.

- **Scalable Parallel Processing**: The system automatically scales across available CPU cores, with workers processing different ranges simultaneously. The round-robin work assignment ensures even distribution of computational load.

- **Result Aggregation and Cleanup**: The boss actor collects results from all workers, maintains a comprehensive list of valid sequences, and ensures proper termination when all work units complete, outputting both individual results and total count.

## How to Run

### Prerequisites
- [Gleam](https://gleam.run/getting-started/installing/) installed
- Erlang/OTP runtime (usually bundled with Gleam installation)

### Installation
```bash
# Clone the repository and install dependencies
git clone <repository-url>
cd sum_of_consecutive_squares_v2
gleam deps download

# Build the project
gleam build
```

The program requires two command-line arguments: `gleam run <N> <k>`
Where:
- **N**: The upper bound for starting positions (integer)
- **k**: The length of consecutive integer sequences (integer)

Example: Find sequences of length 24 in range 1-1000000
```bash
gleam run 1000000 24
```




### Performance Analysis

The efficiency of the parallel processing model is highly dependent on the configuration of workers and the size of the work units they process. Through experimentation, we've optimized two key parameters to achieve a balance between maximizing parallelism and minimizing overhead.

### Performance Metrics

The following table summarizes the performance across various runs. The "Ratio" is calculated as `(user_time + system_time) / real_time`, and "CPU Utilization (%)" represents this ratio as a percentage. A ratio greater than 1.0 (or 100%) indicates that multiple CPU cores are being used effectively.

| Command | User Time (s) | Sys Time (s) | Real Time (s) | Ratio | CPU Utilization (%) |
| :--- | :--- | :--- | :--- | :--- | :--- |
| `gleam run 1000 3` | 0.10 | 0.15 | 0.155 | 1.61 | 161% |
| `gleam run 1000 4` | 0.10 | 0.17 | 0.099 | 2.73 | 272% |
| `gleam run 1000 5` | 0.10 | 0.15 | 0.097 | 2.58 | 258% |
| `gleam run 10000 3` | 0.10 | 0.16 | 0.096 | 2.71 | 271% |
| `gleam run 10000 4` | 0.10 | 0.16 | 0.099 | 2.63 | 263% |
| `gleam run 50000 3` | 0.10 | 0.17 | 0.101 | 2.67 | 267% |
| `gleam run 100000 3` | 0.10 | 0.16 | 0.099 | 2.63 | 263% |
| `gleam run 500000 3` | 0.14 | 0.16 | 0.105 | 2.86 | 286% |
| `gleam run 1000000 3` | 0.19 | 0.17 | 0.117 | 3.08 | 308% |
| `gleam run 1000000 4` | 0.20 | 0.16 | 0.113 | 3.19 | 319% |
| **`gleam run 999999 240`** | **2.72** | **0.32** | **0.539** | **5.64** | **564%** |

The run with `N=999999` and `k=240` shows the best CPU utilization at **564%** (a ratio of 5.64), demonstrating highly effective parallel processing on a multi-core system.

### Rationale for Parameter Selection

#### `let num_workers = 8`  // Parallel workers

The number of workers is fixed at 8. This value was chosen to align with the number of available CPU cores on the development and testing machine.

*   **Maximizing Parallelism**: By setting the number of workers equal to the number of physical cores, we can ensure that each worker runs on a dedicated core. This minimizes the overhead from context switching that would occur if there were more workers than cores.
*   **Full Utilization**: Having a worker for each core ensures that the CPU's processing power is fully leveraged. The high CPU utilization (e.g., 564%) in our optimal test case confirms that multiple cores are actively engaged in computation simultaneously.

#### `let work_unit_size = int.max(100, n / 50)`  // Dynamic work unit sizing

A dynamic strategy is used to determine the size of each work unit (the range of numbers a worker processes at one time).

*   **`int.max(100, ...)` - Avoiding Overhead**: This sets a *minimum* work unit size of 100. For small problem sizes (`N`), this prevents the creation of excessively small work units. The overhead of message passing (sending a work unit to an actor and receiving the result) can be greater than the computation time for a very small unit, making parallelism inefficient. A minimum size ensures that each unit involves a meaningful amount of computation.
*   **`... , n / 50)` - Load Balancing**: This makes the work unit size proportional to the total problem size `N`, effectively creating about 50 work units to be distributed among the 8 workers. This approach provides a good balance:
    *   It creates enough work units to keep all workers busy, ensuring good load balancing. If one worker gets a slightly "slower" chunk, others can pick up new chunks, preventing cores from becoming idle.
    *   It avoids creating too many work units, which would increase the total message-passing overhead and diminish the gains from parallelism.

This combination of a fixed number of workers matching the core count and a dynamic, balanced work unit size allows the program to scale efficiently across different problem sizes.