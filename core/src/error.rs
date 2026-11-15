use std::fmt;

#[derive(Debug, Clone, PartialEq)]
pub enum NoteError {
    NotFound(String),
    InvalidTitle(String),
    AlreadyExists(String),
    Io(String),
}

impl fmt::Display for NoteError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            NoteError::NotFound(s) => write!(f, "not found: {s}"),
            NoteError::InvalidTitle(s) => write!(f, "invalid title: {s}"),
            NoteError::AlreadyExists(s) => write!(f, "already exists: {s}"),
            NoteError::Io(s) => write!(f, "io error: {s}"),
        }
    }
}

impl std::error::Error for NoteError {}

impl From<std::io::Error> for NoteError {
    fn from(e: std::io::Error) -> Self {
        NoteError::Io(e.to_string())
    }
}
