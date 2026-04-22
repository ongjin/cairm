use serde::{Deserialize, Serialize};
use streaming_iterator::StreamingIterator;
use tree_sitter::{Language, Node, Parser, Query, QueryCursor};

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct SymbolRow {
    pub name: String,
    pub kind: SymbolKind,
    pub line: u32,
}

#[repr(u8)]
#[derive(Debug, Clone, Copy, Serialize, Deserialize, PartialEq, Eq)]
pub enum SymbolKind {
    Class = 0,
    Struct = 1,
    Enum = 2,
    Function = 3,
    Method = 4,
    Variable = 5,
    Constant = 6,
    Interface = 7,
}

fn lang_for_ext(ext: &str) -> Option<(Language, &'static str)> {
    match ext {
        "swift" => Some((tree_sitter_swift::LANGUAGE.into(), SWIFT_Q)),
        "ts" => Some((tree_sitter_typescript::LANGUAGE_TYPESCRIPT.into(), TS_Q)),
        "tsx" => Some((tree_sitter_typescript::LANGUAGE_TSX.into(), TS_Q)),
        "py" => Some((tree_sitter_python::LANGUAGE.into(), PY_Q)),
        "rs" => Some((tree_sitter_rust::LANGUAGE.into(), RUST_Q)),
        _ => None,
    }
}

const SWIFT_Q: &str = r#"
(class_declaration name: (type_identifier) @class)
(protocol_declaration name: (type_identifier) @interface)
(function_declaration name: (simple_identifier) @function)
"#;
const TS_Q: &str = r#"
(class_declaration name: (type_identifier) @class)
(interface_declaration name: (type_identifier) @interface)
(function_declaration name: (identifier) @function)
(method_definition name: (property_identifier) @method)
"#;
const PY_Q: &str = r#"
(class_definition name: (identifier) @class)
(function_definition name: (identifier) @function)
"#;
const RUST_Q: &str = r#"
(struct_item name: (type_identifier) @struct)
(enum_item name: (type_identifier) @enum)
(function_item name: (identifier) @function)
(impl_item) @method
"#;

fn kind_from_capture(name: &str) -> SymbolKind {
    match name {
        "class" => SymbolKind::Class,
        "struct" => SymbolKind::Struct,
        "enum" => SymbolKind::Enum,
        "interface" => SymbolKind::Interface,
        "function" => SymbolKind::Function,
        "method" => SymbolKind::Method,
        _ => SymbolKind::Variable,
    }
}

pub fn extract_from_file(path: &std::path::Path) -> Vec<SymbolRow> {
    let ext = match path.extension().and_then(|e| e.to_str()) {
        Some(e) => e,
        None => return Vec::new(),
    };
    let (lang, query_src) = match lang_for_ext(ext) {
        Some(x) => x,
        None => return Vec::new(),
    };
    let src = match std::fs::read_to_string(path) {
        Ok(s) => s,
        Err(_) => return Vec::new(),
    };

    let mut parser = Parser::new();
    if parser.set_language(&lang).is_err() {
        return Vec::new();
    }
    let tree = match parser.parse(&src, None) {
        Some(t) => t,
        None => return Vec::new(),
    };
    let query = match Query::new(&lang, query_src) {
        Ok(q) => q,
        Err(_) => return Vec::new(),
    };

    let mut cursor = QueryCursor::new();
    let capture_names = query.capture_names();
    let mut out = Vec::new();
    let mut matches = cursor.matches(&query, tree.root_node(), src.as_bytes());
    while let Some(mat) = matches.next() {
        for cap in mat.captures {
            let node: Node = cap.node;
            let cap_name = capture_names[cap.index as usize];
            let name = match node.utf8_text(src.as_bytes()) {
                Ok(n) => n.to_string(),
                Err(_) => continue,
            };
            out.push(SymbolRow {
                name,
                kind: kind_from_capture(cap_name),
                line: node.start_position().row as u32 + 1,
            });
        }
    }
    out
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::fs;
    use tempfile::TempDir;

    #[test]
    fn swift_extracts_class_and_func() {
        let tmp = TempDir::new().unwrap();
        let p = tmp.path().join("x.swift");
        fs::write(&p, "class Foo { func bar() {} }").unwrap();
        let syms = extract_from_file(&p);
        let names: Vec<&str> = syms.iter().map(|s| s.name.as_str()).collect();
        assert!(names.contains(&"Foo"));
        assert!(names.contains(&"bar"));
    }

    #[test]
    fn rust_extracts_fn_and_struct() {
        let tmp = TempDir::new().unwrap();
        let p = tmp.path().join("x.rs");
        fs::write(&p, "struct Foo; fn bar() {}").unwrap();
        let syms = extract_from_file(&p);
        let names: Vec<&str> = syms.iter().map(|s| s.name.as_str()).collect();
        assert!(names.contains(&"Foo"));
        assert!(names.contains(&"bar"));
    }

    #[test]
    fn unsupported_language_returns_empty() {
        let tmp = TempDir::new().unwrap();
        let p = tmp.path().join("x.xyz");
        fs::write(&p, "nothing").unwrap();
        assert!(extract_from_file(&p).is_empty());
    }
}
