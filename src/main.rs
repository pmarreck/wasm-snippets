use std::io::{self, Read};

fn quicksort(slice: &mut [String]) {
    if slice.len() <= 1 {
        return;
    }

    let len = slice.len();
    let pivot_index = len / 2;
    slice.swap(pivot_index, len - 1);

    let mut store_index = 0;
    for i in 0..len - 1 {
        if slice[i] <= slice[len - 1] {
            slice.swap(i, store_index);
            store_index += 1;
        }
    }

    slice.swap(store_index, len - 1);
    let (left, right_with_pivot) = slice.split_at_mut(store_index);
    let (_, right) = right_with_pivot.split_first_mut().unwrap();

    quicksort(left);
    quicksort(right);
}

fn main() -> io::Result<()> {
    let mut buffer = String::new();
    io::stdin().read_to_string(&mut buffer)?;

    if buffer.is_empty() {
        return Ok(());
    }

    let had_trailing_newline = buffer.ends_with('\n');
    let mut lines: Vec<String> = buffer.lines().map(|line| line.to_string()).collect();

    if lines.is_empty() {
        if had_trailing_newline {
            print!("\n");
        }
        return Ok(());
    }

    quicksort(&mut lines);

    for (idx, line) in lines.iter().enumerate() {
        if idx > 0 {
            print!("\n");
        }
        print!("{}", line);
    }

    if had_trailing_newline {
        print!("\n");
    }

    Ok(())
}
