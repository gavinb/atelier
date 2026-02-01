#[rustler::nif]
fn scan_code(code: String, forbidden: Vec<String>) -> (bool, Vec<String>) {
    let mut found = Vec::new();
    
    for word in forbidden {
        if code.contains(&word) {
            found.push(word);
        }
    }

    let is_safe = found.is_empty();
    (is_safe, found)
}

rustler::init!("Elixir.Atelier.Native.Scanner");
