// Rust sample file - Advanced patterns demonstrating Rust 2024 Edition features
// This file showcases idiomatic Rust patterns, async programming, and architectural patterns

#![allow(dead_code, unused_variables, unused_imports)]

// =============================================================================
// MODULE SYSTEM AND IMPORTS
// =============================================================================

use std::collections::{BTreeMap, HashMap, HashSet, VecDeque};
use std::fmt::{self, Debug, Display, Formatter};
use std::future::Future;
use std::hash::Hash;
use std::marker::PhantomData;
use std::ops::{Add, Deref, DerefMut, Mul};
use std::pin::Pin;
use std::sync::atomic::{AtomicBool, AtomicU64, Ordering};
use std::sync::Arc;
use std::time::{Duration, Instant};

use tokio::sync::{broadcast, mpsc, oneshot, Mutex, RwLock, Semaphore};
use tokio::time::{sleep, timeout};

// =============================================================================
// TYPE ALIASES AND NEWTYPE PATTERNS
// =============================================================================

/// Type alias for common result type
pub type Result<T> = std::result::Result<T, AppError>;

/// Type alias for async boxed futures
pub type BoxFuture<'a, T> = Pin<Box<dyn Future<Output = T> + Send + 'a>>;

/// Type alias for callback functions
pub type Callback<T> = Box<dyn Fn(T) -> Result<()> + Send + Sync>;

/// Newtype pattern for user IDs - provides type safety
#[derive(Debug, Clone, PartialEq, Eq, Hash, PartialOrd, Ord)]
pub struct UserId(String);

impl UserId {
    pub fn new(id: impl Into<String>) -> Self {
        Self(id.into())
    }

    pub fn as_str(&self) -> &str {
        &self.0
    }

    pub fn into_inner(self) -> String {
        self.0
    }
}

impl Display for UserId {
    fn fmt(&self, f: &mut Formatter<'_>) -> fmt::Result {
        write!(f, "{}", self.0)
    }
}

impl From<String> for UserId {
    fn from(s: String) -> Self {
        Self(s)
    }
}

impl From<&str> for UserId {
    fn from(s: &str) -> Self {
        Self(s.to_string())
    }
}

/// Newtype for email addresses with validation
#[derive(Debug, Clone, PartialEq, Eq, Hash)]
pub struct Email(String);

impl Email {
    pub fn new(email: impl Into<String>) -> Result<Self> {
        let email = email.into();
        if email.contains('@') && email.contains('.') {
            Ok(Self(email))
        } else {
            Err(AppError::ValidationFailed(vec![
                "Invalid email format".to_string(),
            ]))
        }
    }

    pub fn as_str(&self) -> &str {
        &self.0
    }
}

impl Display for Email {
    fn fmt(&self, f: &mut Formatter<'_>) -> fmt::Result {
        write!(f, "{}", self.0)
    }
}

/// Newtype for positive integers
#[derive(Debug, Clone, Copy, PartialEq, Eq, PartialOrd, Ord, Hash)]
pub struct PositiveInt(u64);

impl PositiveInt {
    pub fn new(value: u64) -> Option<Self> {
        if value > 0 {
            Some(Self(value))
        } else {
            None
        }
    }

    pub fn get(&self) -> u64 {
        self.0
    }
}

impl Add for PositiveInt {
    type Output = Self;

    fn add(self, rhs: Self) -> Self::Output {
        Self(self.0 + rhs.0)
    }
}

impl Mul for PositiveInt {
    type Output = Self;

    fn mul(self, rhs: Self) -> Self::Output {
        Self(self.0 * rhs.0)
    }
}

// =============================================================================
// ERROR HANDLING WITH THISERROR PATTERN
// =============================================================================

#[derive(Debug, Clone)]
pub enum AppError {
    NotFound(String),
    ValidationFailed(Vec<String>),
    DatabaseError(String),
    Unauthorized,
    Forbidden { resource: String, action: String },
    InternalError(String),
    Timeout { operation: String, duration: Duration },
    RateLimited { retry_after: Duration },
    Conflict { resource: String, reason: String },
    NetworkError(String),
    ParseError { input: String, expected: String },
    ConfigError(String),
}

impl Display for AppError {
    fn fmt(&self, f: &mut Formatter<'_>) -> fmt::Result {
        match self {
            Self::NotFound(msg) => write!(f, "Not found: {}", msg),
            Self::ValidationFailed(errors) => {
                write!(f, "Validation failed: {}", errors.join(", "))
            }
            Self::DatabaseError(msg) => write!(f, "Database error: {}", msg),
            Self::Unauthorized => write!(f, "Unauthorized"),
            Self::Forbidden { resource, action } => {
                write!(f, "Forbidden: cannot {} on {}", action, resource)
            }
            Self::InternalError(msg) => write!(f, "Internal error: {}", msg),
            Self::Timeout { operation, duration } => {
                write!(f, "Timeout after {:?} on operation: {}", duration, operation)
            }
            Self::RateLimited { retry_after } => {
                write!(f, "Rate limited, retry after: {:?}", retry_after)
            }
            Self::Conflict { resource, reason } => {
                write!(f, "Conflict on {}: {}", resource, reason)
            }
            Self::NetworkError(msg) => write!(f, "Network error: {}", msg),
            Self::ParseError { input, expected } => {
                write!(f, "Parse error: expected {} but got '{}'", expected, input)
            }
            Self::ConfigError(msg) => write!(f, "Configuration error: {}", msg),
        }
    }
}

impl std::error::Error for AppError {}

impl AppError {
    /// Check if error is retryable
    pub fn is_retryable(&self) -> bool {
        matches!(
            self,
            Self::NetworkError(_) | Self::Timeout { .. } | Self::RateLimited { .. }
        )
    }

    /// Get HTTP status code equivalent
    pub fn status_code(&self) -> u16 {
        match self {
            Self::NotFound(_) => 404,
            Self::ValidationFailed(_) => 400,
            Self::Unauthorized => 401,
            Self::Forbidden { .. } => 403,
            Self::Conflict { .. } => 409,
            Self::RateLimited { .. } => 429,
            Self::Timeout { .. } => 504,
            _ => 500,
        }
    }
}

// =============================================================================
// TRAITS WITH DEFAULT IMPLEMENTATIONS AND ASSOCIATED TYPES
// =============================================================================

/// Trait demonstrating associated types and default implementations
pub trait Entity: Clone + Send + Sync + 'static {
    /// Associated type for the entity's ID
    type Id: Clone + Debug + Hash + Eq + Send + Sync;

    /// Get the entity's ID
    fn id(&self) -> &Self::Id;

    /// Get the entity's creation timestamp (default implementation)
    fn created_at(&self) -> Option<Instant> {
        None
    }

    /// Check if entity is valid (default implementation)
    fn is_valid(&self) -> bool {
        true
    }

    /// Convert to JSON-like representation (default implementation)
    fn to_map(&self) -> HashMap<String, String>
    where
        Self: Debug,
    {
        let mut map = HashMap::new();
        map.insert("debug".to_string(), format!("{:?}", self));
        map
    }
}

/// Trait for auditable entities
pub trait Auditable: Entity {
    fn audit_log(&self) -> Vec<AuditEntry>;
    fn last_modified_by(&self) -> Option<UserId>;
    fn version(&self) -> u64;
}

/// Trait for soft-deletable entities
pub trait SoftDeletable: Entity {
    fn is_deleted(&self) -> bool;
    fn deleted_at(&self) -> Option<Instant>;
    fn mark_deleted(&mut self);
    fn restore(&mut self);
}

/// Audit entry for tracking changes
#[derive(Debug, Clone)]
pub struct AuditEntry {
    pub timestamp: Instant,
    pub action: AuditAction,
    pub user_id: Option<UserId>,
    pub details: HashMap<String, String>,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum AuditAction {
    Created,
    Updated,
    Deleted,
    Restored,
    AccessGranted,
    AccessRevoked,
}

/// Trait with generics and where clauses
pub trait Mapper<S, T>
where
    S: Clone + Send,
    T: Clone + Send,
{
    fn map(&self, source: S) -> T;
    fn map_many(&self, sources: Vec<S>) -> Vec<T> {
        sources.into_iter().map(|s| self.map(s)).collect()
    }
}

/// Trait for serializable data
pub trait Serializable {
    type Output;
    type Error: std::error::Error;

    fn serialize(&self) -> std::result::Result<Self::Output, Self::Error>;
    fn deserialize(data: Self::Output) -> std::result::Result<Self, Self::Error>
    where
        Self: Sized;
}

/// Trait for cacheable items
pub trait Cacheable: Clone + Send + Sync {
    type Key: Hash + Eq + Clone + Send + Sync;

    fn cache_key(&self) -> Self::Key;
    fn ttl(&self) -> Duration {
        Duration::from_secs(300) // 5 minutes default
    }
    fn is_stale(&self, cached_at: Instant) -> bool {
        cached_at.elapsed() > self.ttl()
    }
}

// =============================================================================
// STRUCT PATTERNS - TUPLE STRUCTS, UNIT STRUCTS, NAMED FIELDS
// =============================================================================

/// Unit struct for marker types
#[derive(Debug, Clone, Copy, Default)]
pub struct Validated;

#[derive(Debug, Clone, Copy, Default)]
pub struct Unvalidated;

/// Tuple struct for coordinates
#[derive(Debug, Clone, Copy, PartialEq)]
pub struct Point(pub f64, pub f64);

impl Point {
    pub fn origin() -> Self {
        Self(0.0, 0.0)
    }

    pub fn distance(&self, other: &Point) -> f64 {
        let dx = self.0 - other.0;
        let dy = self.1 - other.1;
        (dx * dx + dy * dy).sqrt()
    }
}

/// Tuple struct for RGB colors
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct Rgb(pub u8, pub u8, pub u8);

impl Rgb {
    pub const BLACK: Self = Self(0, 0, 0);
    pub const WHITE: Self = Self(255, 255, 255);
    pub const RED: Self = Self(255, 0, 0);
    pub const GREEN: Self = Self(0, 255, 0);
    pub const BLUE: Self = Self(0, 0, 255);

    pub fn to_hex(&self) -> String {
        format!("#{:02x}{:02x}{:02x}", self.0, self.1, self.2)
    }

    pub fn from_hex(hex: &str) -> Option<Self> {
        let hex = hex.trim_start_matches('#');
        if hex.len() != 6 {
            return None;
        }
        let r = u8::from_str_radix(&hex[0..2], 16).ok()?;
        let g = u8::from_str_radix(&hex[2..4], 16).ok()?;
        let b = u8::from_str_radix(&hex[4..6], 16).ok()?;
        Some(Self(r, g, b))
    }
}

/// Named fields struct - User entity
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct User {
    pub id: UserId,
    pub name: String,
    pub email: Email,
    pub role: Role,
    pub metadata: HashMap<String, String>,
    pub settings: UserSettings,
    pub status: UserStatus,
    created_at: Instant,
    updated_at: Instant,
}

impl Entity for User {
    type Id = UserId;

    fn id(&self) -> &Self::Id {
        &self.id
    }

    fn created_at(&self) -> Option<Instant> {
        Some(self.created_at)
    }
}

impl Cacheable for User {
    type Key = UserId;

    fn cache_key(&self) -> Self::Key {
        self.id.clone()
    }

    fn ttl(&self) -> Duration {
        Duration::from_secs(600) // 10 minutes for users
    }
}

/// User settings struct
#[derive(Debug, Clone, PartialEq, Eq, Default)]
pub struct UserSettings {
    pub theme: Theme,
    pub notifications_enabled: bool,
    pub language: String,
    pub timezone: String,
    pub preferences: HashMap<String, String>,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Default)]
pub enum Theme {
    #[default]
    Light,
    Dark,
    System,
    HighContrast,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Default)]
pub enum UserStatus {
    #[default]
    Active,
    Inactive,
    Suspended,
    PendingVerification,
    Deleted,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Default)]
pub enum Role {
    SuperAdmin,
    Admin,
    Moderator,
    #[default]
    User,
    Guest,
    Bot,
}

impl Role {
    pub fn permissions(&self) -> Vec<Permission> {
        match self {
            Self::SuperAdmin => vec![
                Permission::Read,
                Permission::Write,
                Permission::Delete,
                Permission::Admin,
                Permission::ManageUsers,
                Permission::ManageSystem,
            ],
            Self::Admin => vec![
                Permission::Read,
                Permission::Write,
                Permission::Delete,
                Permission::Admin,
                Permission::ManageUsers,
            ],
            Self::Moderator => vec![Permission::Read, Permission::Write, Permission::Delete],
            Self::User => vec![Permission::Read, Permission::Write],
            Self::Guest => vec![Permission::Read],
            Self::Bot => vec![Permission::Read, Permission::Write],
        }
    }

    pub fn can(&self, permission: Permission) -> bool {
        self.permissions().contains(&permission)
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub enum Permission {
    Read,
    Write,
    Delete,
    Admin,
    ManageUsers,
    ManageSystem,
}

// =============================================================================
// ENUM VARIANTS WITH DATA
// =============================================================================

/// Complex enum with various data patterns
#[derive(Debug, Clone)]
pub enum Message {
    /// Unit variant
    Ping,
    /// Unit variant
    Pong,
    /// Tuple variant with single value
    Text(String),
    /// Tuple variant with multiple values
    Binary(Vec<u8>, String),
    /// Struct variant
    Request {
        id: u64,
        method: String,
        params: HashMap<String, String>,
        timeout: Option<Duration>,
    },
    /// Struct variant for responses
    Response {
        id: u64,
        status: ResponseStatus,
        data: Option<String>,
        error: Option<AppError>,
    },
    /// Nested enum variant
    Command(Command),
    /// Boxed recursive variant
    Batch(Vec<Box<Message>>),
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ResponseStatus {
    Ok,
    Error,
    Pending,
    Cancelled,
}

#[derive(Debug, Clone)]
pub enum Command {
    Start { task_id: String },
    Stop { task_id: String, force: bool },
    Restart { task_id: String, delay: Option<Duration> },
    Status,
    Shutdown { graceful: bool },
    Configure(HashMap<String, String>),
}

impl Message {
    pub fn is_control(&self) -> bool {
        matches!(self, Self::Ping | Self::Pong | Self::Command(_))
    }

    pub fn id(&self) -> Option<u64> {
        match self {
            Self::Request { id, .. } | Self::Response { id, .. } => Some(*id),
            _ => None,
        }
    }
}

/// Event enum for the event sourcing pattern
#[derive(Debug, Clone)]
pub enum DomainEvent {
    UserCreated {
        user_id: UserId,
        name: String,
        email: Email,
        timestamp: Instant,
    },
    UserUpdated {
        user_id: UserId,
        changes: Vec<FieldChange>,
        timestamp: Instant,
    },
    UserDeleted {
        user_id: UserId,
        reason: Option<String>,
        timestamp: Instant,
    },
    RoleAssigned {
        user_id: UserId,
        old_role: Role,
        new_role: Role,
        assigned_by: UserId,
        timestamp: Instant,
    },
    SessionStarted {
        session_id: String,
        user_id: UserId,
        ip_address: String,
        user_agent: String,
        timestamp: Instant,
    },
    SessionEnded {
        session_id: String,
        reason: SessionEndReason,
        timestamp: Instant,
    },
}

#[derive(Debug, Clone)]
pub struct FieldChange {
    pub field: String,
    pub old_value: Option<String>,
    pub new_value: Option<String>,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum SessionEndReason {
    Logout,
    Timeout,
    Revoked,
    SystemShutdown,
}

// =============================================================================
// LIFETIMES - EXPLICIT ANNOTATIONS
// =============================================================================

/// Struct with explicit lifetime annotation
#[derive(Debug)]
pub struct Borrowed<'a> {
    data: &'a str,
    prefix: &'a str,
}

impl<'a> Borrowed<'a> {
    pub fn new(data: &'a str, prefix: &'a str) -> Self {
        Self { data, prefix }
    }

    pub fn formatted(&self) -> String {
        format!("{}: {}", self.prefix, self.data)
    }
}

/// Multiple lifetimes
#[derive(Debug)]
pub struct MultiLifetime<'a, 'b> {
    first: &'a str,
    second: &'b str,
}

impl<'a, 'b> MultiLifetime<'a, 'b> {
    pub fn new(first: &'a str, second: &'b str) -> Self {
        Self { first, second }
    }

    /// Returns reference with shorter lifetime
    pub fn shorter(&self) -> &str
    where
        'a: 'b,
    {
        self.second
    }
}

/// Lifetime with generics
#[derive(Debug)]
pub struct Container<'a, T: 'a> {
    items: Vec<&'a T>,
    name: String,
}

impl<'a, T: 'a + Debug> Container<'a, T> {
    pub fn new(name: impl Into<String>) -> Self {
        Self {
            items: Vec::new(),
            name: name.into(),
        }
    }

    pub fn add(&mut self, item: &'a T) {
        self.items.push(item);
    }

    pub fn get(&self, index: usize) -> Option<&T> {
        self.items.get(index).copied()
    }

    pub fn len(&self) -> usize {
        self.items.len()
    }

    pub fn is_empty(&self) -> bool {
        self.items.is_empty()
    }
}

/// Static lifetime example
pub struct StaticRef {
    message: &'static str,
}

impl StaticRef {
    pub const fn new(message: &'static str) -> Self {
        Self { message }
    }

    pub fn get(&self) -> &'static str {
        self.message
    }
}

/// Function with lifetime elision and explicit annotation
pub fn longest<'a>(x: &'a str, y: &'a str) -> &'a str {
    if x.len() > y.len() {
        x
    } else {
        y
    }
}

/// Function returning reference with explicit lifetime
pub fn first_word<'a>(s: &'a str) -> &'a str {
    let bytes = s.as_bytes();
    for (i, &item) in bytes.iter().enumerate() {
        if item == b' ' {
            return &s[0..i];
        }
    }
    s
}

// =============================================================================
// GENERICS WITH TRAIT BOUNDS AND WHERE CLAUSES
// =============================================================================

/// Generic struct with trait bounds
#[derive(Debug)]
pub struct GenericCache<K, V>
where
    K: Hash + Eq + Clone + Send + Sync,
    V: Clone + Send + Sync,
{
    storage: HashMap<K, CacheEntry<V>>,
    max_size: usize,
    default_ttl: Duration,
}

#[derive(Debug, Clone)]
struct CacheEntry<V> {
    value: V,
    created_at: Instant,
    ttl: Duration,
    hits: u64,
}

impl<K, V> GenericCache<K, V>
where
    K: Hash + Eq + Clone + Send + Sync,
    V: Clone + Send + Sync,
{
    pub fn new(max_size: usize, default_ttl: Duration) -> Self {
        Self {
            storage: HashMap::new(),
            max_size,
            default_ttl,
        }
    }

    pub fn get(&mut self, key: &K) -> Option<V> {
        if let Some(entry) = self.storage.get_mut(key) {
            if entry.created_at.elapsed() < entry.ttl {
                entry.hits += 1;
                return Some(entry.value.clone());
            }
            // Entry is stale, will be removed
        }
        self.storage.remove(key);
        None
    }

    pub fn set(&mut self, key: K, value: V) {
        self.set_with_ttl(key, value, self.default_ttl);
    }

    pub fn set_with_ttl(&mut self, key: K, value: V, ttl: Duration) {
        // Evict if at capacity
        if self.storage.len() >= self.max_size {
            self.evict_oldest();
        }

        let entry = CacheEntry {
            value,
            created_at: Instant::now(),
            ttl,
            hits: 0,
        };
        self.storage.insert(key, entry);
    }

    pub fn remove(&mut self, key: &K) -> Option<V> {
        self.storage.remove(key).map(|e| e.value)
    }

    pub fn clear(&mut self) {
        self.storage.clear();
    }

    pub fn len(&self) -> usize {
        self.storage.len()
    }

    pub fn is_empty(&self) -> bool {
        self.storage.is_empty()
    }

    fn evict_oldest(&mut self) {
        if let Some((oldest_key, _)) = self
            .storage
            .iter()
            .min_by_key(|(_, entry)| entry.created_at)
        {
            let key = oldest_key.clone();
            self.storage.remove(&key);
        }
    }

    pub fn cleanup_stale(&mut self) -> usize {
        let stale_keys: Vec<K> = self
            .storage
            .iter()
            .filter(|(_, entry)| entry.created_at.elapsed() >= entry.ttl)
            .map(|(k, _)| k.clone())
            .collect();

        let count = stale_keys.len();
        for key in stale_keys {
            self.storage.remove(&key);
        }
        count
    }
}

/// Generic function with multiple trait bounds
pub fn process_items<T, F, R>(items: Vec<T>, processor: F) -> Vec<R>
where
    T: Clone + Send + Debug,
    F: Fn(T) -> R + Send + Sync,
    R: Send,
{
    items.into_iter().map(processor).collect()
}

/// Generic function with impl Trait
pub fn create_iterator(start: i32, end: i32) -> impl Iterator<Item = i32> {
    (start..end).filter(|x| x % 2 == 0).map(|x| x * 2)
}

/// Higher-kinded types simulation using associated types
pub trait Functor {
    type Inner;
    type Mapped<U>;

    fn map<U, F>(self, f: F) -> Self::Mapped<U>
    where
        F: FnOnce(Self::Inner) -> U;
}

impl<T> Functor for Option<T> {
    type Inner = T;
    type Mapped<U> = Option<U>;

    fn map<U, F>(self, f: F) -> Self::Mapped<U>
    where
        F: FnOnce(Self::Inner) -> U,
    {
        self.map(f)
    }
}

// =============================================================================
// SMART POINTERS
// =============================================================================

/// Example demonstrating Box for heap allocation
pub struct TreeNode<T> {
    value: T,
    left: Option<Box<TreeNode<T>>>,
    right: Option<Box<TreeNode<T>>>,
}

impl<T: Clone + Ord> TreeNode<T> {
    pub fn new(value: T) -> Self {
        Self {
            value,
            left: None,
            right: None,
        }
    }

    pub fn insert(&mut self, value: T) {
        if value < self.value {
            match &mut self.left {
                Some(left) => left.insert(value),
                None => self.left = Some(Box::new(TreeNode::new(value))),
            }
        } else {
            match &mut self.right {
                Some(right) => right.insert(value),
                None => self.right = Some(Box::new(TreeNode::new(value))),
            }
        }
    }

    pub fn contains(&self, value: &T) -> bool {
        if value == &self.value {
            true
        } else if value < &self.value {
            self.left.as_ref().map_or(false, |l| l.contains(value))
        } else {
            self.right.as_ref().map_or(false, |r| r.contains(value))
        }
    }

    pub fn in_order(&self) -> Vec<T> {
        let mut result = Vec::new();
        if let Some(left) = &self.left {
            result.extend(left.in_order());
        }
        result.push(self.value.clone());
        if let Some(right) = &self.right {
            result.extend(right.in_order());
        }
        result
    }
}

/// Reference counted pointer example
pub mod rc_example {
    use std::cell::RefCell;
    use std::rc::Rc;

    #[derive(Debug)]
    pub struct Node<T> {
        value: T,
        children: RefCell<Vec<Rc<Node<T>>>>,
        parent: RefCell<Option<Rc<Node<T>>>>,
    }

    impl<T> Node<T> {
        pub fn new(value: T) -> Rc<Self> {
            Rc::new(Self {
                value,
                children: RefCell::new(Vec::new()),
                parent: RefCell::new(None),
            })
        }

        pub fn add_child(parent: &Rc<Self>, child: Rc<Self>) {
            *child.parent.borrow_mut() = Some(Rc::clone(parent));
            parent.children.borrow_mut().push(child);
        }

        pub fn value(&self) -> &T {
            &self.value
        }

        pub fn children_count(&self) -> usize {
            self.children.borrow().len()
        }
    }
}

/// Thread-safe reference counted pointer example
pub mod arc_example {
    use std::sync::atomic::{AtomicUsize, Ordering};
    use std::sync::Arc;
    use tokio::sync::RwLock;

    #[derive(Debug)]
    pub struct SharedState<T> {
        data: RwLock<T>,
        access_count: AtomicUsize,
    }

    impl<T> SharedState<T> {
        pub fn new(data: T) -> Arc<Self> {
            Arc::new(Self {
                data: RwLock::new(data),
                access_count: AtomicUsize::new(0),
            })
        }

        pub async fn read(&self) -> tokio::sync::RwLockReadGuard<'_, T> {
            self.access_count.fetch_add(1, Ordering::SeqCst);
            self.data.read().await
        }

        pub async fn write(&self) -> tokio::sync::RwLockWriteGuard<'_, T> {
            self.access_count.fetch_add(1, Ordering::SeqCst);
            self.data.write().await
        }

        pub fn access_count(&self) -> usize {
            self.access_count.load(Ordering::SeqCst)
        }
    }
}

/// RefCell for interior mutability
pub mod refcell_example {
    use std::cell::RefCell;

    #[derive(Debug)]
    pub struct Counter {
        value: RefCell<i32>,
    }

    impl Counter {
        pub fn new(initial: i32) -> Self {
            Self {
                value: RefCell::new(initial),
            }
        }

        pub fn increment(&self) {
            *self.value.borrow_mut() += 1;
        }

        pub fn decrement(&self) {
            *self.value.borrow_mut() -= 1;
        }

        pub fn get(&self) -> i32 {
            *self.value.borrow()
        }

        pub fn set(&self, value: i32) {
            *self.value.borrow_mut() = value;
        }
    }
}

// =============================================================================
// BUILDER PATTERN
// =============================================================================

impl User {
    pub fn builder() -> UserBuilder {
        UserBuilder::default()
    }

    pub fn validate(&self) -> Result<()> {
        let mut errors = Vec::new();

        if self.name.len() < 2 {
            errors.push("Name must be at least 2 characters".to_string());
        }

        if self.name.len() > 100 {
            errors.push("Name must be at most 100 characters".to_string());
        }

        if errors.is_empty() {
            Ok(())
        } else {
            Err(AppError::ValidationFailed(errors))
        }
    }
}

#[derive(Default)]
pub struct UserBuilder {
    id: Option<UserId>,
    name: Option<String>,
    email: Option<Email>,
    role: Role,
    metadata: HashMap<String, String>,
    settings: UserSettings,
    status: UserStatus,
}

impl UserBuilder {
    pub fn id(mut self, id: impl Into<UserId>) -> Self {
        self.id = Some(id.into());
        self
    }

    pub fn name(mut self, name: impl Into<String>) -> Self {
        self.name = Some(name.into());
        self
    }

    pub fn email(mut self, email: Email) -> Self {
        self.email = Some(email);
        self
    }

    pub fn email_str(mut self, email: impl Into<String>) -> Result<Self> {
        self.email = Some(Email::new(email)?);
        Ok(self)
    }

    pub fn role(mut self, role: Role) -> Self {
        self.role = role;
        self
    }

    pub fn status(mut self, status: UserStatus) -> Self {
        self.status = status;
        self
    }

    pub fn metadata(mut self, key: impl Into<String>, value: impl Into<String>) -> Self {
        self.metadata.insert(key.into(), value.into());
        self
    }

    pub fn settings(mut self, settings: UserSettings) -> Self {
        self.settings = settings;
        self
    }

    pub fn theme(mut self, theme: Theme) -> Self {
        self.settings.theme = theme;
        self
    }

    pub fn notifications(mut self, enabled: bool) -> Self {
        self.settings.notifications_enabled = enabled;
        self
    }

    pub fn build(self) -> Result<User> {
        let now = Instant::now();

        let user = User {
            id: self.id.ok_or_else(|| {
                AppError::ValidationFailed(vec!["ID is required".to_string()])
            })?,
            name: self.name.ok_or_else(|| {
                AppError::ValidationFailed(vec!["Name is required".to_string()])
            })?,
            email: self.email.ok_or_else(|| {
                AppError::ValidationFailed(vec!["Email is required".to_string()])
            })?,
            role: self.role,
            metadata: self.metadata,
            settings: self.settings,
            status: self.status,
            created_at: now,
            updated_at: now,
        };

        user.validate()?;
        Ok(user)
    }
}

/// Type-state builder pattern for compile-time validation
pub mod typestate_builder {
    use super::*;

    pub struct HttpRequestBuilder<MethodSet, UrlSet> {
        method: Option<HttpMethod>,
        url: Option<String>,
        headers: HashMap<String, String>,
        body: Option<Vec<u8>>,
        timeout: Duration,
        _method_marker: PhantomData<MethodSet>,
        _url_marker: PhantomData<UrlSet>,
    }

    pub struct NotSet;
    pub struct Set;

    #[derive(Debug, Clone, Copy, PartialEq, Eq)]
    pub enum HttpMethod {
        Get,
        Post,
        Put,
        Patch,
        Delete,
        Head,
        Options,
    }

    impl Default for HttpRequestBuilder<NotSet, NotSet> {
        fn default() -> Self {
            Self {
                method: None,
                url: None,
                headers: HashMap::new(),
                body: None,
                timeout: Duration::from_secs(30),
                _method_marker: PhantomData,
                _url_marker: PhantomData,
            }
