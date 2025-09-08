import gleam/erlang/process.{type Subject}
import gleam/int
import gleam/io
import gleam/list
import gleam/otp/actor
import gleam/result
import argv
import gleam/float

pub type WorkerMessage {
  WorkRequest(start: Int, end: Int, k: Int, boss: Subject(BossMessage))
  Stop
}

pub type BossMessage {
  WorkResult(results: List(Int))
  WorkerFinished
  StartComputation(n: Int, k: Int, reply_with: Subject(BossMessage))
}

pub type BossState {
  BossState(
    all_results: List(Int),
    workers_completed: Int,
    total_work_units: Int,
    self_subject: Subject(BossMessage),
  )
}

// Perfect square check
pub fn is_perfect_square(n: Int) -> Bool {
  case int.square_root(n) {
    Ok(root) -> {
      let root_int = float.round(root)
      root_int * root_int == n
    }
    Error(_) -> False
  }
}

// Sum of consecutive squares
pub fn sum_of_consecutive_squares(start: Int, k: Int) -> Int {
  list.range(start, start + k - 1)
  |> list.map(fn(x) { x * x })
  |> list.fold(0, int.add)
}

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
      let results = 
        list.range(start, end)
        |> list.filter(fn(i) { is_valid_sequence(i, k) })
      
      process.send(boss, WorkResult(results))
      process.send(boss, WorkerFinished)
      actor.continue(Nil)
    }
    Stop -> actor.stop()
  }
}

// Boss actor that coordinates work and collects results
pub fn boss_handler(
  state: BossState,
  message: BossMessage,
) -> actor.Next(BossState, BossMessage) {
  case message {
    StartComputation(n, k, reply_with) -> {
      let num_workers = 8  
      let work_unit_size = int.max(100, n / 50) 
      
      let work_ranges = create_work_ranges(1, n, work_unit_size)
      let total_units = list.length(work_ranges)
      
      let workers = list.range(1, num_workers)
        |> list.map(fn(_) {
          case actor.new(Nil) |> actor.on_message(worker_handler) |> actor.start {
            Ok(started_actor) -> Ok(started_actor.data)
            Error(e) -> Error(e)
          }
        })
        |> result.values 
      
      assign_work_to_workers(workers, work_ranges, k, reply_with)
      
      actor.continue(BossState(
        all_results: [],
        workers_completed: 0,
        total_work_units: total_units,
        self_subject: reply_with,
      ))
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
          state.all_results
          |> list.each(fn(x) { io.println(int.to_string(x)) })
          
          io.println("RESULTS FOUND: " <> int.to_string(list.length(state.all_results)))
          
          actor.stop()
        }
        False -> {
          actor.continue(BossState(
            ..state,
            workers_completed: completed,
          ))
        }
      }
    }
  }
}

pub fn create_work_ranges(start: Int, end: Int, unit_size: Int) -> List(#(Int, Int)) {
  case start > end {
    True -> []
    False -> {
      let range_end = int.min(start + unit_size - 1, end)
      [#(start, range_end), ..create_work_ranges(range_end + 1, end, unit_size)]
    }
  }
}

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
  case argv.load().arguments {
    [n_str, k_str] -> {
      case int.parse(n_str), int.parse(k_str) {
        Ok(n), Ok(k) -> {
          let initial_state = BossState(
            all_results: [],
            workers_completed: 0,
            total_work_units: 0,
            self_subject: process.new_subject(), 
          )
          
          case actor.new(initial_state) |> actor.on_message(boss_handler) |> actor.start {
            Ok(boss_actor) -> {
              let boss_subject = boss_actor.data
              process.send(boss_subject, StartComputation(n, k, boss_subject))
              
              let _monitor = process.monitor(boss_actor.pid)
              let selector = process.new_selector()
                |> process.select_monitors(fn(down) { down })
              
              case process.selector_receive_forever(selector) {
                _ -> Nil
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
      io.println("Example: gleam run 100 4")
    }
  }
}