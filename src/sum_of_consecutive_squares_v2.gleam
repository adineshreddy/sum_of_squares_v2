import gleam/erlang/process.{type Subject}
import gleam/int
import gleam/io
import gleam/list
import gleam/otp/actor
import gleam/result
import argv
import gleam/float

// Message types for actor communication
pub type WorkerMessage {
  WorkRequest(start: Int, end: Int, k: Int, boss: Subject(BossMessage))
  Stop
}

pub type BossMessage {
  WorkResult(results: List(Int))
  WorkerFinished
  StartComputation(n: Int, k: Int, reply_with: Subject(BossMessage))
  BatchComplete(batch_id: Int)
}

// State types
pub type BossState {
  BossState(
    all_results: List(Int),
    workers_completed: Int,
    total_work_units: Int,
    self_subject: Subject(BossMessage),
    current_batch: Int,
    total_batches: Int,
    batch_size: Int,
    n: Int,
    k: Int,
    workers: List(Subject(WorkerMessage)),
  )
}

// Perfect square detection - optimized with early exit
pub fn is_perfect_square(n: Int) -> Bool {
  case n {
    x if x < 0 -> False
    0 -> True
    1 -> True
    _ -> {
      case int.square_root(n) {
        Ok(root) -> {
          let root_int = float.round(root)
          root_int * root_int == n
        }
        Error(_) -> False
      }
    }
  }
}

// Sum of consecutive squares - optimized with direct calculation
pub fn sum_of_consecutive_squares(start: Int, k: Int) -> Int {
  // Use mathematical formula for better performance
  sum_squares_range(start, start + k - 1)
}

// Direct calculation of sum of squares in a range - tail recursive
fn sum_squares_range(start: Int, end: Int) -> Int {
  sum_squares_range_acc(start, end, 0)
}

fn sum_squares_range_acc(start: Int, end: Int, acc: Int) -> Int {
  case start > end {
    True -> acc
    False -> sum_squares_range_acc(start + 1, end, acc + start * start)
  }
}

// Check if sequence starting at 'start' with length 'k' gives perfect square
pub fn is_valid_sequence(start: Int, k: Int) -> Bool {
  let sum = sum_of_consecutive_squares(start, k)
  is_perfect_square(sum)
}

// Worker actor that processes a range of starting positions
pub fn worker_handler(
  _state: Nil,
  message: WorkerMessage,
) -> actor.Next(Nil, WorkerMessage) {
  case message {
    WorkRequest(start, end, k, boss) -> {
      // Process the range and find valid sequences
      let results = find_valid_sequences_in_range(start, end, k, [])
      
      // Send results back to boss
      process.send(boss, WorkResult(results))
      process.send(boss, WorkerFinished)
      actor.continue(Nil)
    }
    Stop -> actor.stop()
  }
}

// Optimized range processing without intermediate list creation
fn find_valid_sequences_in_range(start: Int, end: Int, k: Int, acc: List(Int)) -> List(Int) {
  case start > end {
    True -> list.reverse(acc)
    False -> {
      case is_valid_sequence(start, k) {
        True -> find_valid_sequences_in_range(start + 1, end, k, [start, ..acc])
        False -> find_valid_sequences_in_range(start + 1, end, k, acc)
      }
    }
  }
}

// Boss actor that coordinates work and collects results
pub fn boss_handler(
  state: BossState,
  message: BossMessage,
) -> actor.Next(BossState, BossMessage) {
  case message {
    StartComputation(n, k, reply_with) -> {
      // High parallelism configuration
      let num_workers = 1500
      let batch_size = 1500  // Process in batches to manage memory
      let total_batches = int.max(1, n / batch_size)
      
      io.println("Starting computation with " <> int.to_string(num_workers) <> " workers")
      io.println("Processing " <> int.to_string(total_batches) <> " batches of size " <> int.to_string(batch_size))
      
      // Create all worker actors upfront
      let workers = create_workers(num_workers)
      
      let initial_state = BossState(
        all_results: [],
        workers_completed: 0,
        total_work_units: 0,
        self_subject: reply_with,
        current_batch: 1,
        total_batches: total_batches,
        batch_size: batch_size,
        n: n,
        k: k,
        workers: workers,
      )
      
      // Start first batch
      let updated_state = start_batch(initial_state)
      actor.continue(updated_state)
    }
    
    WorkResult(results) -> {
      let updated_results = list.append(state.all_results, results)
      actor.continue(BossState(
        ..state,
        all_results: updated_results,
      ))
    }
    
    WorkerFinished -> {
      let completed = state.workers_completed + 1
      
      case completed >= state.total_work_units {
        True -> {
          // Current batch completed
          case state.current_batch >= state.total_batches {
            True -> {
              // All batches completed - output results and stop
              state.all_results
              |> list.each(fn(x) { io.println(int.to_string(x)) })
              
              io.println("RESULTS FOUND: " <> int.to_string(list.length(state.all_results)))
              
              // Stop all workers
              list.each(state.workers, fn(worker) {
                process.send(worker, Stop)
              })
              
              actor.stop()
            }
            False -> {
              // Start next batch
              io.println("Batch " <> int.to_string(state.current_batch) <> " completed. Starting batch " <> int.to_string(state.current_batch + 1))
              
              let next_state = BossState(
                ..state,
                current_batch: state.current_batch + 1,
                workers_completed: 0,
                total_work_units: 0,
              )
              
              let updated_state = start_batch(next_state)
              actor.continue(updated_state)
            }
          }
        }
        False -> {
          actor.continue(BossState(
            ..state,
            workers_completed: completed,
          ))
        }
      }
    }
    
    BatchComplete(_batch_id) -> {
      actor.continue(state)
    }
  }
}

// Create all worker actors upfront
fn create_workers(num_workers: Int) -> List(Subject(WorkerMessage)) {
  list.range(1, num_workers)
  |> list.map(fn(_) {
    case actor.new(Nil) |> actor.on_message(worker_handler) |> actor.start {
      Ok(started_actor) -> Ok(started_actor.data)
      Error(_) -> Error("Failed to create worker")
    }
  })
  |> result.values
}

// Start processing a batch
fn start_batch(state: BossState) -> BossState {
  let x = state.current_batch - 1
  let batch_start = x * state.batch_size + 1
  let batch_end = int.min(state.current_batch * state.batch_size, state.n)
  
  // Calculate optimal work unit size for high parallelism
  // Smaller work units = better load balancing across 1500 workers
  let available_workers = list.length(state.workers)
  let batch_work = batch_end - batch_start + 1
  let y = available_workers * 4
  let work_unit_size = int.max(1, batch_work / y)  // 4x work units per worker for better distribution
  
  // Create work ranges for this batch
  let work_ranges = create_work_ranges(batch_start, batch_end, work_unit_size)
  let total_units = list.length(work_ranges)
  
  io.println("Batch " <> int.to_string(state.current_batch) <> ": processing " <> int.to_string(batch_start) <> " to " <> int.to_string(batch_end))
  io.println("Work units: " <> int.to_string(total_units) <> ", unit size: " <> int.to_string(work_unit_size))
  
  // Distribute work among workers
  assign_work_to_workers(state.workers, work_ranges, state.k, state.self_subject)
  
  BossState(
    ..state,
    workers_completed: 0,
    total_work_units: total_units,
  )
}

// Create work ranges for distribution - optimized for many small units
pub fn create_work_ranges(start: Int, end: Int, unit_size: Int) -> List(#(Int, Int)) {
  create_work_ranges_acc(start, end, unit_size, [])
}

fn create_work_ranges_acc(start: Int, end: Int, unit_size: Int, acc: List(#(Int, Int))) -> List(#(Int, Int)) {
  case start > end {
    True -> list.reverse(acc)
    False -> {
      let range_end = int.min(start + unit_size - 1, end)
      create_work_ranges_acc(range_end + 1, end, unit_size, [#(start, range_end), ..acc])
    }
  }
}

// Distribute work ranges to available workers - optimized round robin
pub fn assign_work_to_workers(
  workers: List(Subject(WorkerMessage)),
  work_ranges: List(#(Int, Int)),
  k: Int,
  boss: Subject(BossMessage),
) -> Nil {
  assign_work_round_robin(workers, work_ranges, k, boss, 0)
}

pub fn assign_work_round_robin(
  workers: List(Subject(WorkerMessage)),
  work_ranges: List(#(Int, Int)),
  k: Int,
  boss: Subject(BossMessage),
  worker_index: Int,
) -> Nil {
  case work_ranges, workers {
    [], _ -> Nil  // No more work
    _, [] -> Nil  // No workers available
    [#(start, end), ..remaining_ranges], _ -> {
      let worker_count = list.length(workers)
      let current_worker_idx = worker_index % worker_count
      
      // Get worker at current index
      case list.drop(workers, current_worker_idx) |> list.first {
        Ok(worker) -> {
          process.send(worker, WorkRequest(start, end, k, boss))
          assign_work_round_robin(
            workers, 
            remaining_ranges, 
            k, 
            boss, 
            worker_index + 1
          )
        }
        Error(_) -> {
          // Skip this range if worker not found
          assign_work_round_robin(
            workers, 
            remaining_ranges, 
            k, 
            boss, 
            worker_index + 1
          )
        }
      }
    }
  }
}

pub fn main() {
  // Parse command line arguments using argv
  case argv.load().arguments {
    [n_str, k_str] -> {
      case int.parse(n_str), int.parse(k_str) {
        Ok(n), Ok(k) -> {
          // Start the boss actor system
          let initial_state = BossState(
            all_results: [],
            workers_completed: 0,
            total_work_units: 0,
            self_subject: process.new_subject(),
            current_batch: 0,
            total_batches: 0,
            batch_size: 1500,
            n: n,
            k: k,
            workers: [],
          )
          
          case actor.new(initial_state) |> actor.on_message(boss_handler) |> actor.start {
            Ok(boss_actor) -> {
              let boss_subject = boss_actor.data
              process.send(boss_subject, StartComputation(n, k, boss_subject))
              
              // Monitor the boss actor and wait for it to terminate
              let _monitor = process.monitor(boss_actor.pid)
              let selector = process.new_selector()
                |> process.select_monitors(fn(down) { down })
              
              // Wait for boss to finish
              case process.selector_receive_forever(selector) {
                _ -> Nil  // Boss actor has terminated, program can exit
              }
            }
            Error(_) -> {
              io.println("Failed to start boss actor")
            }
          }
        }
        _, _ -> {
          io.println("Error: Invalid arguments. Usage: lukas <N> <k>")
        }
      }
    }
    _ -> {
      io.println("Usage: lukas <N> <k>")
      io.println("Where N is the upper bound and k is the sequence length")
      io.println("Example: gleam run 1000000 24")
    }
  }
}