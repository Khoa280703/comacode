// Go sample file - Advanced patterns with modern Go 1.21+ features
// This file demonstrates comprehensive Go patterns including generics,
// concurrency, error handling, HTTP handlers, middleware, and more.
package main

import (
	"bytes"
	"context"
	"crypto/rand"
	"crypto/sha256"
	"encoding/base64"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"hash"
	"io"
	"log"
	"log/slog"
	"net/http"
	"net/url"
	"os"
	"os/signal"
	"reflect"
	"regexp"
	"runtime"
	"slices"
	"sort"
	"strconv"
	"strings"
	"sync"
	"sync/atomic"
	"syscall"
	"time"
)

// ============================================================================
// Custom Errors - Sentinel errors and error wrapping patterns
// ============================================================================

var (
	ErrNotFound        = errors.New("resource not found")
	ErrValidation      = errors.New("validation failed")
	ErrUnauthorized    = errors.New("unauthorized")
	ErrForbidden       = errors.New("forbidden")
	ErrConflict        = errors.New("resource conflict")
	ErrInternalServer  = errors.New("internal server error")
	ErrTimeout         = errors.New("operation timeout")
	ErrRateLimited     = errors.New("rate limit exceeded")
	ErrServiceDown     = errors.New("service unavailable")
	ErrInvalidInput    = errors.New("invalid input")
	ErrDatabaseError   = errors.New("database error")
	ErrCacheError      = errors.New("cache error")
	ErrNetworkError    = errors.New("network error")
	ErrSerializationError = errors.New("serialization error")
)

// AppError wraps errors with context, stack trace, and metadata
type AppError struct {
	Err       error
	Message   string
	Code      int
	RequestID string
	Stack     string
	Metadata  map[string]interface{}
	Timestamp time.Time
}

func (e *AppError) Error() string {
	if e.Message != "" {
		return fmt.Sprintf("[%s] %s: %v", e.RequestID, e.Message, e.Err)
	}
	return e.Err.Error()
}

func (e *AppError) Unwrap() error {
	return e.Err
}

func (e *AppError) Is(target error) bool {
	return errors.Is(e.Err, target)
}

func (e *AppError) WithMetadata(key string, value interface{}) *AppError {
	if e.Metadata == nil {
		e.Metadata = make(map[string]interface{})
	}
	e.Metadata[key] = value
	return e
}

func NewAppError(err error, message string, code int) *AppError {
	return &AppError{
		Err:       err,
		Message:   message,
		Code:      code,
		Timestamp: time.Now(),
		Stack:     captureStackTrace(2),
	}
}

func captureStackTrace(skip int) string {
	var pcs [32]uintptr
	n := runtime.Callers(skip+1, pcs[:])
	frames := runtime.CallersFrames(pcs[:n])
	var sb strings.Builder
	for {
		frame, more := frames.Next()
		fmt.Fprintf(&sb, "%s:%d %s\n", frame.File, frame.Line, frame.Function)
		if !more {
			break
		}
	}
	return sb.String()
}

// ValidationError holds multiple validation errors
type ValidationError struct {
	Errors []FieldError
}

type FieldError struct {
	Field   string `json:"field"`
	Message string `json:"message"`
	Value   any    `json:"value,omitempty"`
}

func (v *ValidationError) Error() string {
	if len(v.Errors) == 0 {
		return "validation failed"
	}
	var msgs []string
	for _, e := range v.Errors {
		msgs = append(msgs, fmt.Sprintf("%s: %s", e.Field, e.Message))
	}
	return strings.Join(msgs, "; ")
}

func (v *ValidationError) Add(field, message string, value any) {
	v.Errors = append(v.Errors, FieldError{Field: field, Message: message, Value: value})
}

func (v *ValidationError) HasErrors() bool {
	return len(v.Errors) > 0
}

// ============================================================================
// Result Type Pattern - Go 1.21+ Generics
// ============================================================================

// Result represents either a success value or an error
type Result[T any] struct {
	value T
	err   error
}

func Ok[T any](data T) Result[T] {
	return Result[T]{value: data}
}

func Fail[T any](err error) Result[T] {
	var zero T
	return Result[T]{value: zero, err: err}
}

func (r Result[T]) IsOk() bool {
	return r.err == nil
}

func (r Result[T]) IsErr() bool {
	return r.err != nil
}

func (r Result[T]) Unwrap() T {
	if r.err != nil {
		panic(fmt.Sprintf("called Unwrap on error result: %v", r.err))
	}
	return r.value
}

func (r Result[T]) UnwrapOr(defaultValue T) T {
	if r.err != nil {
		return defaultValue
	}
	return r.value
}

func (r Result[T]) UnwrapOrElse(fn func() T) T {
	if r.err != nil {
		return fn()
	}
	return r.value
}

func (r Result[T]) Error() error {
	return r.err
}

func (r Result[T]) Value() (T, error) {
	return r.value, r.err
}

// Map transforms the value if successful
func Map[T, U any](r Result[T], fn func(T) U) Result[U] {
	if r.err != nil {
		return Fail[U](r.err)
	}
	return Ok(fn(r.value))
}

// FlatMap chains operations that may fail
func FlatMap[T, U any](r Result[T], fn func(T) Result[U]) Result[U] {
	if r.err != nil {
		return Fail[U](r.err)
	}
	return fn(r.value)
}

// Option type for nullable values
type Option[T any] struct {
	value   T
	present bool
}

func Some[T any](value T) Option[T] {
	return Option[T]{value: value, present: true}
}

func None[T any]() Option[T] {
	return Option[T]{present: false}
}

func (o Option[T]) IsSome() bool {
	return o.present
}

func (o Option[T]) IsNone() bool {
	return !o.present
}

func (o Option[T]) Unwrap() T {
	if !o.present {
		panic("called Unwrap on None")
	}
	return o.value
}

func (o Option[T]) UnwrapOr(defaultValue T) T {
	if !o.present {
		return defaultValue
	}
	return o.value
}

func (o Option[T]) Get() (T, bool) {
	return o.value, o.present
}

// ============================================================================
// Entity Types - User, Organization, etc.
// ============================================================================

type Role string

const (
	RoleAdmin     Role = "admin"
	RoleUser      Role = "user"
	RoleGuest     Role = "guest"
	RoleModerator Role = "moderator"
	RoleSupport   Role = "support"
)

func (r Role) IsValid() bool {
	switch r {
	case RoleAdmin, RoleUser, RoleGuest, RoleModerator, RoleSupport:
		return true
	}
	return false
}

func (r Role) HasPermission(permission string) bool {
	permissions := map[Role][]string{
		RoleAdmin:     {"read", "write", "delete", "admin"},
		RoleModerator: {"read", "write", "moderate"},
		RoleUser:      {"read", "write"},
		RoleGuest:     {"read"},
		RoleSupport:   {"read", "support"},
	}
	perms, ok := permissions[r]
	if !ok {
		return false
	}
	return slices.Contains(perms, permission)
}

type UserStatus string

const (
	UserStatusActive    UserStatus = "active"
	UserStatusInactive  UserStatus = "inactive"
	UserStatusSuspended UserStatus = "suspended"
	UserStatusPending   UserStatus = "pending"
)

// User entity with comprehensive validation
type User struct {
	ID            string            `json:"id"`
	Username      string            `json:"username"`
	Email         string            `json:"email"`
	PasswordHash  string            `json:"-"`
	Name          string            `json:"name"`
	Role          Role              `json:"role"`
	Status        UserStatus        `json:"status"`
	Avatar        string            `json:"avatar,omitempty"`
	Bio           string            `json:"bio,omitempty"`
	Metadata      map[string]string `json:"metadata,omitempty"`
	Preferences   UserPreferences   `json:"preferences"`
	CreatedAt     time.Time         `json:"created_at"`
	UpdatedAt     time.Time         `json:"updated_at,omitempty"`
	LastLoginAt   *time.Time        `json:"last_login_at,omitempty"`
	EmailVerified bool              `json:"email_verified"`
	MFAEnabled    bool              `json:"mfa_enabled"`
	Version       int64             `json:"version"` // Optimistic locking
}

type UserPreferences struct {
	Theme           string `json:"theme"`
	Language        string `json:"language"`
	Timezone        string `json:"timezone"`
	EmailNotify     bool   `json:"email_notify"`
	PushNotify      bool   `json:"push_notify"`
	TwoFactorMethod string `json:"two_factor_method,omitempty"`
}

// Validate performs comprehensive user validation
func (u *User) Validate() error {
	ve := &ValidationError{}

	// Username validation
	if len(u.Username) < 3 {
		ve.Add("username", "must be at least 3 characters", u.Username)
	}
	if len(u.Username) > 30 {
		ve.Add("username", "must be at most 30 characters", u.Username)
	}
	usernameRegex := regexp.MustCompile(`^[a-zA-Z0-9_-]+$`)
	if !usernameRegex.MatchString(u.Username) {
		ve.Add("username", "must contain only letters, numbers, underscores, and hyphens", u.Username)
	}

	// Email validation
	if u.Email == "" {
		ve.Add("email", "is required", nil)
	} else {
		emailRegex := regexp.MustCompile(`^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$`)
		if !emailRegex.MatchString(u.Email) {
			ve.Add("email", "must be a valid email address", u.Email)
		}
	}

	// Name validation
	if len(u.Name) < 2 {
		ve.Add("name", "must be at least 2 characters", u.Name)
	}
	if len(u.Name) > 100 {
		ve.Add("name", "must be at most 100 characters", u.Name)
	}

	// Role validation
	if !u.Role.IsValid() {
		ve.Add("role", "must be a valid role", u.Role)
	}

	// Bio length
	if len(u.Bio) > 500 {
		ve.Add("bio", "must be at most 500 characters", len(u.Bio))
	}

	// Preferences validation
	if u.Preferences.Theme != "" && u.Preferences.Theme != "light" && u.Preferences.Theme != "dark" && u.Preferences.Theme != "system" {
		ve.Add("preferences.theme", "must be light, dark, or system", u.Preferences.Theme)
	}

	if ve.HasErrors() {
		return &AppError{
			Err:     ErrValidation,
			Message: ve.Error(),
			Code:    http.StatusBadRequest,
		}
	}

	return nil
}

// Organization entity
type Organization struct {
	ID          string            `json:"id"`
	Name        string            `json:"name"`
	Slug        string            `json:"slug"`
	Description string            `json:"description,omitempty"`
	Logo        string            `json:"logo,omitempty"`
	Website     string            `json:"website,omitempty"`
	Members     []OrganizationMember `json:"members,omitempty"`
	Settings    OrganizationSettings `json:"settings"`
	CreatedAt   time.Time         `json:"created_at"`
	UpdatedAt   time.Time         `json:"updated_at"`
}

type OrganizationMember struct {
	UserID   string    `json:"user_id"`
	Role     string    `json:"role"`
	JoinedAt time.Time `json:"joined_at"`
}

type OrganizationSettings struct {
	AllowPublicProjects   bool   `json:"allow_public_projects"`
	RequireMFA            bool   `json:"require_mfa"`
	AllowedEmailDomains   []string `json:"allowed_email_domains,omitempty"`
	MaxMembers            int    `json:"max_members"`
	BillingPlan           string `json:"billing_plan"`
}

// ============================================================================
// Repository Pattern with Generics
// ============================================================================

// Entity is a constraint for entities with ID
type Entity interface {
	GetID() string
	SetID(id string)
}

func (u *User) GetID() string         { return u.ID }
func (u *User) SetID(id string)       { u.ID = id }
func (o *Organization) GetID() string { return o.ID }
func (o *Organization) SetID(id string) { o.ID = id }

// Repository interface with generics
type Repository[T Entity] interface {
	FindByID(ctx context.Context, id string) (*T, error)
	FindAll(ctx context.Context, opts QueryOptions) ([]T, error)
	Create(ctx context.Context, entity *T) error
	Update(ctx context.Context, entity *T) error
	Delete(ctx context.Context, id string) error
	Count(ctx context.Context, opts QueryOptions) (int64, error)
	Exists(ctx context.Context, id string) (bool, error)
}

// QueryOptions for flexible querying
type QueryOptions struct {
	Filters     map[string]interface{}
	Sort        []SortOption
	Pagination  *Pagination
	Fields      []string
	Include     []string
	Search      string
}

type SortOption struct {
	Field string
	Desc  bool
}

type Pagination struct {
	Page     int
	PageSize int
	Cursor   string
}

func (p *Pagination) Offset() int {
	if p.Page <= 0 {
		return 0
	}
	return (p.Page - 1) * p.PageSize
}

func (p *Pagination) Limit() int {
	if p.PageSize <= 0 {
		return 20
	}
	if p.PageSize > 100 {
		return 100
	}
	return p.PageSize
}

// PagedResult for paginated responses
type PagedResult[T any] struct {
	Data       []T    `json:"data"`
	Total      int64  `json:"total"`
	Page       int    `json:"page"`
	PageSize   int    `json:"page_size"`
	TotalPages int    `json:"total_pages"`
	HasNext    bool   `json:"has_next"`
	HasPrev    bool   `json:"has_prev"`
	NextCursor string `json:"next_cursor,omitempty"`
}

// InMemoryRepository implementation with generics
type InMemoryRepository[T Entity] struct {
	mu       sync.RWMutex
	store    map[string]*T
	idGen    func() string
	onUpdate []func(old, new *T)
}

func NewInMemoryRepository[T Entity](idGen func() string) *InMemoryRepository[T] {
	return &InMemoryRepository[T]{
		store: make(map[string]*T),
		idGen: idGen,
	}
}

func (r *InMemoryRepository[T]) FindByID(ctx context.Context, id string) (*T, error) {
	select {
	case <-ctx.Done():
		return nil, ctx.Err()
	default:
	}

	r.mu.RLock()
	defer r.mu.RUnlock()

	entity, ok := r.store[id]
	if !ok {
		return nil, NewAppError(ErrNotFound, fmt.Sprintf("entity %s not found", id), http.StatusNotFound)
	}

	return entity, nil
}

func (r *InMemoryRepository[T]) FindAll(ctx context.Context, opts QueryOptions) ([]T, error) {
	select {
	case <-ctx.Done():
		return nil, ctx.Err()
	default:
	}

	r.mu.RLock()
	defer r.mu.RUnlock()

	result := make([]T, 0, len(r.store))
	for _, entity := range r.store {
		result = append(result, *entity)
	}

	// Apply pagination
	if opts.Pagination != nil {
		offset := opts.Pagination.Offset()
		limit := opts.Pagination.Limit()

		if offset >= len(result) {
			return []T{}, nil
		}

		end := offset + limit
		if end > len(result) {
			end = len(result)
		}

		result = result[offset:end]
	}

	return result, nil
}

func (r *InMemoryRepository[T]) Create(ctx context.Context, entity *T) error {
	select {
	case <-ctx.Done():
		return ctx.Err()
	default:
	}

	r.mu.Lock()
	defer r.mu.Unlock()

	id := (*entity).GetID()
	if id == "" {
		id = r.idGen()
		(*entity).SetID(id)
	}

	if _, exists := r.store[id]; exists {
		return NewAppError(ErrConflict, fmt.Sprintf("entity %s already exists", id), http.StatusConflict)
	}

	r.store[id] = entity
	return nil
}

func (r *InMemoryRepository[T]) Update(ctx context.Context, entity *T) error {
	select {
	case <-ctx.Done():
		return ctx.Err()
	default:
	}

	r.mu.Lock()
	defer r.mu.Unlock()

	id := (*entity).GetID()
	old, exists := r.store[id]
	if !exists {
		return NewAppError(ErrNotFound, fmt.Sprintf("entity %s not found", id), http.StatusNotFound)
	}

	r.store[id] = entity

	// Notify update listeners
	for _, fn := range r.onUpdate {
		fn(old, entity)
	}

	return nil
}

func (r *InMemoryRepository[T]) Delete(ctx context.Context, id string) error {
	select {
	case <-ctx.Done():
		return ctx.Err()
	default:
	}

	r.mu.Lock()
	defer r.mu.Unlock()

	if _, exists := r.store[id]; !exists {
		return NewAppError(ErrNotFound, fmt.Sprintf("entity %s not found", id), http.StatusNotFound)
	}

	delete(r.store, id)
	return nil
}

func (r *InMemoryRepository[T]) Count(ctx context.Context, opts QueryOptions) (int64, error) {
	r.mu.RLock()
	defer r.mu.RUnlock()
	return int64(len(r.store)), nil
}

func (r *InMemoryRepository[T]) Exists(ctx context.Context, id string) (bool, error) {
	r.mu.RLock()
	defer r.mu.RUnlock()
	_, exists := r.store[id]
	return exists, nil
}

func (r *InMemoryRepository[T]) OnUpdate(fn func(old, new *T)) {
	r.mu.Lock()
	defer r.mu.Unlock()
	r.onUpdate = append(r.onUpdate, fn)
}

// ============================================================================
// Event System with Channels
// ============================================================================

type EventType string

const (
	EventUserCreated      EventType = "user.created"
	EventUserUpdated      EventType = "user.updated"
	EventUserDeleted      EventType = "user.deleted"
	EventUserLogin        EventType = "user.login"
	EventUserLogout       EventType = "user.logout"
	EventOrgCreated       EventType = "org.created"
	EventOrgUpdated       EventType = "org.updated"
	EventOrgMemberAdded   EventType = "org.member.added"
	EventOrgMemberRemoved EventType = "org.member.removed"
	EventCacheInvalidated EventType = "cache.invalidated"
	EventRateLimitHit     EventType = "ratelimit.hit"
)

// Event represents a domain event
type Event struct {
	ID        string                 `json:"id"`
	Type      EventType              `json:"type"`
	Payload   interface{}            `json:"payload"`
	Metadata  map[string]string      `json:"metadata,omitempty"`
	Source    string                 `json:"source"`
	Timestamp time.Time              `json:"timestamp"`
	Version   int                    `json:"version"`
}

func NewEvent(eventType EventType, payload interface{}) Event {
	return Event{
		ID:        generateUUID(),
		Type:      eventType,
		Payload:   payload,
		Timestamp: time.Now(),
		Version:   1,
	}
}

func (e *Event) WithMetadata(key, value string) *Event {
	if e.Metadata == nil {
		e.Metadata = make(map[string]string)
	}
	e.Metadata[key] = value
	return e
}

// EventHandler processes events
type EventHandler func(ctx context.Context, event Event) error

// EventBus manages event subscriptions and publishing
type EventBus struct {
	mu          sync.RWMutex
	subscribers map[EventType][]subscription
	handlers    map[EventType][]EventHandler
	eventCh     chan Event
	workerCount int
	wg          sync.WaitGroup
	closed      atomic.Bool
	logger      *slog.Logger
}

type subscription struct {
	ch     chan Event
	filter func(Event) bool
}

type EventBusConfig struct {
	BufferSize  int
	WorkerCount int
	Logger      *slog.Logger
}

func NewEventBus(config EventBusConfig) *EventBus {
	if config.BufferSize <= 0 {
		config.BufferSize = 1000
	}
	if config.WorkerCount <= 0 {
		config.WorkerCount = runtime.NumCPU()
	}
	if config.Logger == nil {
		config.Logger = slog.Default()
	}

	eb := &EventBus{
		subscribers: make(map[EventType][]subscription),
		handlers:    make(map[EventType][]EventHandler),
		eventCh:     make(chan Event, config.BufferSize),
		workerCount: config.WorkerCount,
		logger:      config.Logger,
	}

	// Start workers
	for i := 0; i < config.WorkerCount; i++ {
		eb.wg.Add(1)
		go eb.worker(i)
	}

	return eb
}

func (eb *EventBus) worker(id int) {
	defer eb.wg.Done()
	for event := range eb.eventCh {
		eb.processEvent(event)
	}
}

func (eb *EventBus) processEvent(event Event) {
	eb.mu.RLock()
	subs := eb.subscribers[event.Type]
	handlers := eb.handlers[event.Type]
	eb.mu.RUnlock()

	// Send to channel subscribers
	for _, sub := range subs {
		if sub.filter == nil || sub.filter(event) {
			select {
			case sub.ch <- event:
			default:
				eb.logger.Warn("event channel full, dropping event",
					"event_type", event.Type,
					"event_id", event.ID)
			}
		}
	}

	// Call handlers
	ctx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
	defer cancel()

	for _, handler := range handlers {
		if err := handler(ctx, event); err != nil {
			eb.logger.Error("event handler error",
				"event_type", event.Type,
				"event_id", event.ID,
				"error", err)
		}
	}
}

func (eb *EventBus) Subscribe(eventType EventType, bufferSize int) <-chan Event {
	return eb.SubscribeWithFilter(eventType, bufferSize, nil)
}

func (eb *EventBus) SubscribeWithFilter(eventType EventType, bufferSize int, filter func(Event) bool) <-chan Event {
	eb.mu.Lock()
	defer eb.mu.Unlock()

	ch := make(chan Event, bufferSize)
	eb.subscribers[eventType] = append(eb.subscribers[eventType], subscription{
		ch:     ch,
		filter: filter,
	})
	return ch
}

func (eb *EventBus) On(eventType EventType, handler EventHandler) {
	eb.mu.Lock()
	defer eb.mu.Unlock()
	eb.handlers[eventType] = append(eb.handlers[eventType], handler)
}

func (eb *EventBus) Publish(event Event) {
	if eb.closed.Load() {
		return
	}
	event.Timestamp = time.Now()
	if event.ID == "" {
		event.ID = generateUUID()
	}

	select {
	case eb.eventCh <- event:
	default:
		eb.logger.Warn("event bus buffer full", "event_type", event.Type)
	}
}

func (eb *EventBus) PublishSync(ctx context.Context, event Event) error {
	if eb.closed.Load() {
		return errors.New("event bus closed")
	}
	event.Timestamp = time.Now()
	if event.ID == "" {
		event.ID = generateUUID()
	}

	select {
	case eb.eventCh <- event:
		return nil
	case <-ctx.Done():
		return ctx.Err()
	}
}

func (eb *EventBus) Close() {
	if eb.closed.Swap(true) {
		return
	}
	close(eb.eventCh)
	eb.wg.Wait()
}

// ============================================================================
// Cache with TTL and LRU eviction
// ============================================================================

type CacheEntry[T any] struct {
	Value      T
	ExpiresAt  time.Time
	LastAccess time.Time
	AccessCount int64
}

func (e *CacheEntry[T]) IsExpired() bool {
	return time.Now().After(e.ExpiresAt)
}

type Cache[K comparable, V any] struct {
	mu          sync.RWMutex
	entries     map[K]*CacheEntry[V]
	maxSize     int
	defaultTTL  time.Duration
	onEvict     func(K, V)
	hits        atomic.Int64
	misses      atomic.Int64
	cleanupTick *time.Ticker
	done        chan struct{}
}

type CacheConfig struct {
	MaxSize        int
	DefaultTTL     time.Duration
	CleanupInterval time.Duration
}

func NewCache[K comparable, V any](config CacheConfig) *Cache[K, V] {
	if config.MaxSize <= 0 {
		config.MaxSize = 1000
	}
	if config.DefaultTTL <= 0 {
		config.DefaultTTL = 5 * time.Minute
	}
	if config.CleanupInterval <= 0 {
		config.CleanupInterval = time.Minute
	}

	c := &Cache[K, V]{
		entries:     make(map[K]*CacheEntry[V]),
		maxSize:     config.MaxSize,
		defaultTTL:  config.DefaultTTL,
		cleanupTick: time.NewTicker(config.CleanupInterval),
		done:        make(chan struct{}),
	}

	go c.cleanupLoop()
	return c
}

func (c *Cache[K, V]) Get(key K) (V, bool) {
	c.mu.RLock()
	entry, ok := c.entries[key]
	c.mu.RUnlock()

	var zero V
	if !ok {
		c.misses.Add(1)
		return zero, false
	}

	if entry.IsExpired() {
		c.Delete(key)
		c.misses.Add(1)
		return zero, false
	}

	c.mu.Lock()
	entry.LastAccess = time.Now()
	entry.AccessCount++
	c.mu.Unlock()

	c.hits.Add(1)
	return entry.Value, true
}

func (c *Cache[K, V]) Set(key K, value V) {
	c.SetWithTTL(key, value, c.defaultTTL)
}

func (c *Cache[K, V]) SetWithTTL(key K, value V, ttl time.Duration) {
	c.mu.Lock()
	defer c.mu.Unlock()

	// Evict if at capacity
	if len(c.entries) >= c.maxSize {
		c.evictLRU()
	}

	c.entries[key] = &CacheEntry[V]{
		Value:      value,
		ExpiresAt:  time.Now().Add(ttl),
		LastAccess: time.Now(),
	}
}

func (c *Cache[K, V]) Delete(key K) {
	c.mu.Lock()
	defer c.mu.Unlock()

	if entry, ok := c.entries[key]; ok {
		if c.onEvict != nil {
			c.onEvict(key, entry.Value)
		}
		delete(c.entries, key)
	}
}

func (c *Cache[K, V]) evictLRU() {
	var (
		oldestKey    K
		oldestAccess time.Time
		first        = true
	)

	for key, entry := range c.entries {
		if first || entry.LastAccess.Before(oldestAccess) {
			oldestKey = key
			oldestAccess = entry.LastAccess
			first = false
		}
	}

	if !first {
		if entry, ok := c.entries[oldestKey]; ok && c.onEvict != nil {
			c.onEvict(oldestKey, entry.Value)
		}
		delete(c.entries, oldestKey)
	}
}

func (c *Cache[K, V]) cleanupLoop() {
	for {
		select {
		case <-c.cleanupTick.C:
			c.cleanup()
		case <-c.done:
			return
		}
	}
}

func (c *Cache[K, V]) cleanup() {
	c.mu.Lock()
	defer c.mu.Unlock()

	for key, entry := range c.entries {
		if entry.IsExpired() {
			if c.onEvict != nil {
				c.onEvict(key, entry.Value)
			}
			delete(c.entries, key)
		}
	}
}

func (c *Cache[K, V]) Stats() CacheStats {
	return CacheStats{
		Size:   len(c.entries),
		Hits:   c.hits.Load(),
		Misses: c.misses.Load(),
	}
}

func (c *Cache[K, V]) Close() {
	c.cleanupTick.Stop()
	close(c.done)
}

type CacheStats struct {
	Size   int
	Hits   int64
	Misses int64
}

func (s CacheStats) HitRate() float64 {
	total := s.Hits + s.Misses
	if total == 0 {
		return 0
	}
	return float64(s.Hits) / float64(total)
}

// ============================================================================
// Service Layer with Caching
// ============================================================================

type UserService struct {
	repo     Repository[User]
	cache    *Cache[string, *User]
	eventBus *EventBus
	logger   *slog.Logger
	metrics  *ServiceMetrics
}

type ServiceMetrics struct {
	RequestCount   atomic.Int64
	ErrorCount     atomic.Int64
	LatencySum     atomic.Int64
	CacheHits      atomic.Int64
	CacheMisses    atomic.Int64
}

func NewUserService(repo Repository[User], cache *Cache[string, *User], eventBus *EventBus, logger *slog.Logger) *UserService {
	return &UserService{
		repo:     repo,
		cache:    cache,
		eventBus: eventBus,
		logger:   logger,
		metrics:  &ServiceMetrics{},
	}
}

func (s *UserService) GetByID(ctx context.Context, id string) (*User, error) {
	start := time.Now()
	defer func() {
		s.metrics.RequestCount.Add(1)
		s.metrics.LatencySum.Add(time.Since(start).Milliseconds())
	}()

	// Try cache first
	if user, ok := s.cache.Get(id); ok {
		s.metrics.CacheHits.Add(1)
		s.logger.Debug("cache hit", "user_id", id)
		return user, nil
	}
	s.metrics.CacheMisses.Add(1)

	// Fetch from repository
	user, err := s.repo.FindByID(ctx, id)
	if err != nil {
		s.metrics.ErrorCount.Add(1)
		return nil, err
	}

	// Populate cache
	s.cache.Set(id, user)
	return user, nil
}

func (s *UserService) Create(ctx context.Context, user *User) error {
	// Validate
	if err := user.Validate(); err != nil {
		return err
	}

	// Set defaults
	user.CreatedAt = time.Now()
	user.Status = UserStatusPending
	if user.Role == "" {
		user.Role = RoleUser
	}

	// Hash password if provided
	if user.PasswordHash != "" {
		hashed, err := hashPassword(user.PasswordHash)
		if err != nil {
			return NewAppError(ErrInternalServer, "failed to hash password", http.StatusInternalServerError)
		}
		user.PasswordHash = hashed
	}

	// Create in repository
	if err := s.repo.Create(ctx, user); err != nil {
		s.metrics.ErrorCount.Add(1)
		return err
	}

	// Publish event
	s.eventBus.Publish(NewEvent(EventUserCreated, user))

	s.logger.Info("user created", "user_id", user.ID, "email", user.Email)
	return nil
}

func (s *UserService) Update(ctx context.Context, user *User) error {
	// Validate
	if err := user.Validate(); err != nil {
		return err
	}

	user.UpdatedAt = time.Now()
	user.Version++

	// Update in repository
	if err := s.repo.Update(ctx, user); err != nil {
		s.metrics.ErrorCount.Add(1)
		return err
	}

	// Invalidate cache
	s.cache.Delete(user.ID)

	// Publish event
	s.eventBus.Publish(NewEvent(EventUserUpdated, user))

	s.logger.Info("user updated", "user_id", user.ID)
	return nil
}

func (s *UserService) Delete(ctx context.Context, id string) error {
	// Check exists
	exists, err := s.repo.Exists(ctx, id)
	if err != nil {
		return err
	}
	if !exists {
		return NewAppError(ErrNotFound, "user not found", http.StatusNotFound)
	}

	// Delete from repository
	if err := s.repo.Delete(ctx, id); err != nil {
		s.metrics.ErrorCount.Add(1)
		return err
	}

	// Invalidate cache
	s.cache.Delete(id)

	// Publish event
	s.eventBus.Publish(NewEvent(EventUserDeleted, map[string]string{"id": id}))

	s.logger.Info("user deleted", "user_id", id)
	return nil
}

func (s *UserService) List(ctx context.Context, opts QueryOptions) (*PagedResult[User], error) {
	start := time.Now()
	defer func() {
		s.metrics.RequestCount.Add(1)
		s.metrics.LatencySum.Add(time.Since(start).Milliseconds())
	}()

	users, err := s.repo.FindAll(ctx, opts)
	if err != nil {
		s.metrics.ErrorCount.Add(1)
		return nil, err
	}

	total, err := s.repo.Count(ctx, opts)
	if err != nil {
		return nil, err
	}

	page := 1
	pageSize := 20
	if opts.Pagination != nil {
		page = opts.Pagination.Page
		pageSize = opts.Pagination.Limit()
	}

	totalPages := int(total) / pageSize
	if int(total)%pageSize != 0 {
		totalPages++
	}

	return &PagedResult[User]{
		Data:       users,
		Total:      total,
		Page:       page,
		PageSize:   pageSize,
		TotalPages: totalPages,
		HasNext:    page < totalPages,
		HasPrev:    page > 1,
	}, nil
}

func (s *UserService) GetMetrics() map[string]interface{} {
	cacheStats := s.cache.Stats()
	return map[string]interface{}{
		"request_count":  s.metrics.RequestCount.Load(),
		"error_count":    s.metrics.ErrorCount.Load(),
		"avg_latency_ms": float64(s.metrics.LatencySum.Load()) / float64(max(1, s.metrics.RequestCount.Load())),
		"cache_hits":     s.metrics.CacheHits.Load(),
		"cache_misses":   s.metrics.CacheMisses.Load(),
		"cache_hit_rate": cacheStats.HitRate(),
	}
}

// ============================================================================
// Concurrent Utilities
// ============================================================================

// WorkerPool manages a pool of workers
type WorkerPool struct {
	tasks       chan func()
	results     chan interface{}
	workerCount int
	wg          sync.WaitGroup
	started     atomic.Bool
	stopped     atomic.Bool
}

func NewWorkerPool(workerCount, queueSize int) *WorkerPool {
	return &WorkerPool{
		tasks:       make(chan func(), queueSize),
		results:     make(chan interface{}, queueSize),
		workerCount: workerCount,
	}
}

func (p *WorkerPool) Start() {
	if p.started.Swap(true) {
		return
	}

	for i := 0; i < p.workerCount; i++ {
		p.wg.Add(1)
		go p.worker()
	}
}

func (p *WorkerPool) worker() {
	defer p.wg.Done()
	for task := range p.tasks {
		task()
	}
}

func (p *WorkerPool) Submit(task func()) bool {
	if p.stopped.Load() {
		return false
	}

	select {
	case p.tasks <- task:
		return true
	default:
		return false
	}
}

func (p *WorkerPool) Stop() {
	if p.stopped.Swap(true) {
		return
	}
	close(p.tasks)
	p.wg.Wait()
}

// Semaphore for limiting concurrent operations
type Semaphore struct {
	ch chan struct{}
}

func NewSemaphore(limit int) *Semaphore {
	return &Semaphore{
		ch: make(chan struct{}, limit),
	}
}

func (s *Semaphore) Acquire(ctx context.Context) error {
	select {
	case s.ch <- struct{}{}:
		return nil
	case <-ctx.Done():
		return ctx.Err()
	}
}

func (s *Semaphore) TryAcquire() bool {
	select {
	case s.ch <- struct{}{}:
		return true
	default:
		return false
	}
}

func (s *Semaphore) Release() {
	select {
	case <-s.ch:
	default:
		panic("semaphore: release without acquire")
	}
}

// RateLimiter using token bucket algorithm
type RateLimiter struct {
	mu           sync.Mutex
	tokens       float64
	maxTokens    float64
	refillRate   float64
	lastRefill   time.Time
}

func NewRateLimiter(maxTokens, refillRate float64) *RateLimiter {
	return &RateLimiter{
		tokens:     maxTokens,
		maxTokens:  maxTokens,
		refillRate: refillRate,
		lastRefill: time.Now(),
	}
}

func (r *RateLimiter) Allow() bool {
	return r.AllowN(1)
}

func (r *RateLimiter) AllowN(n float64) bool {
	r.mu.Lock()
	defer r.mu.Unlock()

	now := time.Now()
	elapsed := now.Sub(r.lastRefill).Seconds()
	r.tokens = min(r.maxTokens, r.tokens+elapsed*r.refillRate)
	r.lastRefill = now

	if r.tokens < n {
		return false
	}

	r.tokens -= n
	return true
}

func (r *RateLimiter) Wait(ctx context.Context) error {
	return r.WaitN(ctx, 1)
}

func (r *RateLimiter) WaitN(ctx context.Context, n float64) error {
	for {
		if r.AllowN(n) {
			return nil
		}

		select {
		case <-ctx.Done():
			return ctx.Err()
		case <-time.After(time.Millisecond * 10):
			// Try again
