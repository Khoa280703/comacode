#!/usr/bin/env python3
"""
Comprehensive Python 3.11+ Sample File.

This module demonstrates modern Python patterns including:
- Type hints and generic types
- Dataclasses with validation
- Result and Option types (functional error handling)
- Repository pattern
- Event-driven architecture
- Service layer patterns
- Async utilities and patterns
- Functional programming utilities
- Decorators (sync and async)
- Context managers
- Custom exceptions
- Unit test examples

Author: Advanced Python Patterns Demo
Version: 2.0.0
"""

from __future__ import annotations

import asyncio
import contextlib
import functools
import hashlib
import inspect
import json
import logging
import operator
import os
import re
import secrets
import sys
import threading
import time
import traceback
import uuid
import weakref
from abc import ABC, abstractmethod
from collections import OrderedDict, defaultdict, deque
from collections.abc import (
    AsyncIterator,
    Awaitable,
    Callable,
    Coroutine,
    Iterable,
    Iterator,
    Mapping,
    MutableMapping,
    Sequence,
)
from concurrent.futures import ThreadPoolExecutor
from contextlib import asynccontextmanager, contextmanager
from dataclasses import KW_ONLY, asdict, dataclass, field, replace
from datetime import date, datetime, timedelta, timezone
from decimal import Decimal
from enum import Enum, Flag, IntEnum, StrEnum, auto
from functools import cache, cached_property, lru_cache, partial, reduce, wraps
from io import StringIO
from itertools import chain, cycle, islice, takewhile
from pathlib import Path
from types import TracebackType
from typing import (
    IO,
    Annotated,
    Any,
    ClassVar,
    Concatenate,
    Final,
    Generic,
    Literal,
    NamedTuple,
    Never,
    NewType,
    NoReturn,
    NotRequired,
    Optional,
    ParamSpec,
    Protocol,
    Self,
    TypeAlias,
    TypedDict,
    TypeGuard,
    TypeVar,
    Union,
    cast,
    final,
    get_args,
    get_origin,
    overload,
    runtime_checkable,
)
from unittest import IsolatedAsyncioTestCase, TestCase, main as unittest_main, mock
from urllib.parse import urlencode, urljoin, urlparse

# =============================================================================
# CONFIGURATION AND LOGGING
# =============================================================================

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s - %(name)s - %(levelname)s - %(message)s",
    handlers=[logging.StreamHandler(sys.stdout)],
)
logger = logging.getLogger(__name__)

# =============================================================================
# TYPE VARIABLES AND TYPE ALIASES
# =============================================================================

T = TypeVar("T")
T_co = TypeVar("T_co", covariant=True)
T_contra = TypeVar("T_contra", contravariant=True)
K = TypeVar("K")
V = TypeVar("V")
E = TypeVar("E", bound=Exception)
P = ParamSpec("P")
R = TypeVar("R")

# Custom NewTypes for domain modeling
UserId = NewType("UserId", str)
Email = NewType("Email", str)
Password = NewType("Password", str)
Timestamp = NewType("Timestamp", float)
JSONValue: TypeAlias = (
    dict[str, "JSONValue"] | list["JSONValue"] | str | int | float | bool | None
)
AsyncCallable: TypeAlias = Callable[P, Awaitable[R]]


# =============================================================================
# CUSTOM EXCEPTIONS
# =============================================================================


class BaseAppException(Exception):
    """Base exception for all application errors."""

    def __init__(
        self,
        message: str,
        *,
        code: str | None = None,
        details: dict[str, Any] | None = None,
    ) -> None:
        super().__init__(message)
        self.message = message
        self.code = code or self.__class__.__name__
        self.details = details or {}
        self.timestamp = datetime.now(timezone.utc)

    def to_dict(self) -> dict[str, Any]:
        """Convert exception to dictionary for serialization."""
        return {
            "error": self.code,
            "message": self.message,
            "details": self.details,
            "timestamp": self.timestamp.isoformat(),
        }

    def __repr__(self) -> str:
        return f"{self.__class__.__name__}(message={self.message!r}, code={self.code!r})"


class ValidationError(BaseAppException):
    """Raised when data validation fails."""

    def __init__(
        self,
        message: str,
        field: str | None = None,
        value: Any = None,
        constraints: list[str] | None = None,
    ) -> None:
        super().__init__(
            message,
            code="VALIDATION_ERROR",
            details={
                "field": field,
                "value": str(value) if value is not None else None,
                "constraints": constraints or [],
            },
        )
        self.field = field
        self.value = value
        self.constraints = constraints or []


class NotFoundError(BaseAppException):
    """Raised when a requested resource is not found."""

    def __init__(
        self,
        resource_type: str,
        resource_id: str | None = None,
    ) -> None:
        message = f"{resource_type} not found"
        if resource_id:
            message = f"{resource_type} with ID '{resource_id}' not found"
        super().__init__(
            message,
            code="NOT_FOUND",
            details={"resource_type": resource_type, "resource_id": resource_id},
        )
        self.resource_type = resource_type
        self.resource_id = resource_id


class ConflictError(BaseAppException):
    """Raised when there's a conflict with existing data."""

    def __init__(self, message: str, conflicting_field: str | None = None) -> None:
        super().__init__(
            message,
            code="CONFLICT",
            details={"conflicting_field": conflicting_field},
        )


class AuthenticationError(BaseAppException):
    """Raised when authentication fails."""

    def __init__(self, message: str = "Authentication failed") -> None:
        super().__init__(message, code="AUTHENTICATION_ERROR")


class AuthorizationError(BaseAppException):
    """Raised when authorization fails."""

    def __init__(
        self,
        message: str = "Access denied",
        required_permission: str | None = None,
    ) -> None:
        super().__init__(
            message,
            code="AUTHORIZATION_ERROR",
            details={"required_permission": required_permission},
        )


class RateLimitError(BaseAppException):
    """Raised when rate limit is exceeded."""

    def __init__(
        self,
        message: str = "Rate limit exceeded",
        retry_after: int | None = None,
    ) -> None:
        super().__init__(
            message,
            code="RATE_LIMIT_EXCEEDED",
            details={"retry_after": retry_after},
        )
        self.retry_after = retry_after


class ServiceUnavailableError(BaseAppException):
    """Raised when a service is temporarily unavailable."""

    def __init__(
        self,
        service_name: str,
        reason: str | None = None,
    ) -> None:
        message = f"Service '{service_name}' is temporarily unavailable"
        if reason:
            message = f"{message}: {reason}"
        super().__init__(
            message,
            code="SERVICE_UNAVAILABLE",
            details={"service_name": service_name, "reason": reason},
        )


class ConfigurationError(BaseAppException):
    """Raised when configuration is invalid or missing."""

    def __init__(self, message: str, config_key: str | None = None) -> None:
        super().__init__(
            message,
            code="CONFIGURATION_ERROR",
            details={"config_key": config_key},
        )


# =============================================================================
# ENUMERATIONS
# =============================================================================


class Status(StrEnum):
    """Task or entity status enumeration."""

    PENDING = "pending"
    IN_PROGRESS = "in_progress"
    COMPLETED = "completed"
    FAILED = "failed"
    CANCELLED = "cancelled"
    ARCHIVED = "archived"


class Priority(IntEnum):
    """Priority levels for tasks."""

    LOW = 1
    MEDIUM = 2
    HIGH = 3
    CRITICAL = 4


class UserRole(StrEnum):
    """User role enumeration."""

    GUEST = "guest"
    USER = "user"
    MODERATOR = "moderator"
    ADMIN = "admin"
    SUPER_ADMIN = "super_admin"


class Permission(Flag):
    """Permission flags using Flag enum."""

    NONE = 0
    READ = auto()
    WRITE = auto()
    DELETE = auto()
    ADMIN = auto()
    ALL = READ | WRITE | DELETE | ADMIN


class EventType(StrEnum):
    """Event types for the event system."""

    CREATED = "created"
    UPDATED = "updated"
    DELETED = "deleted"
    ACTIVATED = "activated"
    DEACTIVATED = "deactivated"
    EXPIRED = "expired"


class LogLevel(IntEnum):
    """Custom log levels."""

    TRACE = 5
    DEBUG = 10
    INFO = 20
    WARNING = 30
    ERROR = 40
    CRITICAL = 50


# =============================================================================
# RESULT AND OPTION TYPES (Functional Error Handling)
# =============================================================================


@dataclass(frozen=True, slots=True)
class Ok(Generic[T]):
    """Represents a successful result containing a value."""

    value: T

    def is_ok(self) -> bool:
        return True

    def is_err(self) -> bool:
        return False

    def unwrap(self) -> T:
        """Get the success value."""
        return self.value

    def unwrap_or(self, default: T) -> T:
        """Get the value or a default."""
        return self.value

    def unwrap_or_else(self, f: Callable[[], T]) -> T:
        """Get the value or compute a default."""
        return self.value

    def map(self, f: Callable[[T], R]) -> Result[R]:
        """Map over the success value."""
        return Ok(f(self.value))

    def map_err(self, f: Callable[[Exception], Exception]) -> Result[T]:
        """Map over the error (no-op for Ok)."""
        return self

    def and_then(self, f: Callable[[T], Result[R]]) -> Result[R]:
        """Chain another Result-returning function."""
        return f(self.value)

    def or_else(self, f: Callable[[Exception], Result[T]]) -> Result[T]:
        """Return self for Ok."""
        return self

    def expect(self, message: str) -> T:
        """Get value or raise with custom message."""
        return self.value

    def __bool__(self) -> bool:
        return True


@dataclass(frozen=True, slots=True)
class Err(Generic[T]):
    """Represents a failed result containing an error."""

    error: Exception

    def is_ok(self) -> bool:
        return False

    def is_err(self) -> bool:
        return True

    def unwrap(self) -> Never:
        """Raises the contained error."""
        raise self.error

    def unwrap_or(self, default: T) -> T:
        """Return the default value."""
        return default

    def unwrap_or_else(self, f: Callable[[], T]) -> T:
        """Compute and return the default."""
        return f()

    def map(self, f: Callable[[T], R]) -> Result[R]:
        """Return self (error) unchanged."""
        return Err(self.error)

    def map_err(self, f: Callable[[Exception], Exception]) -> Result[T]:
        """Map over the error."""
        return Err(f(self.error))

    def and_then(self, f: Callable[[T], Result[R]]) -> Result[R]:
        """Return self (error) unchanged."""
        return Err(self.error)

    def or_else(self, f: Callable[[Exception], Result[T]]) -> Result[T]:
        """Try alternative function on error."""
        return f(self.error)

    def expect(self, message: str) -> Never:
        """Raise with custom message."""
        raise type(self.error)(message) from self.error

    def __bool__(self) -> bool:
        return False


Result: TypeAlias = Ok[T] | Err[T]


def try_result(f: Callable[P, R]) -> Callable[P, Result[R]]:
    """Decorator to convert exceptions to Result type."""

    @wraps(f)
    def wrapper(*args: P.args, **kwargs: P.kwargs) -> Result[R]:
        try:
            return Ok(f(*args, **kwargs))
        except Exception as e:
            return Err(e)

    return wrapper


async def try_result_async(
    f: Callable[P, Awaitable[R]]
) -> Callable[P, Awaitable[Result[R]]]:
    """Async decorator to convert exceptions to Result type."""

    @wraps(f)
    async def wrapper(*args: P.args, **kwargs: P.kwargs) -> Result[R]:
        try:
            return Ok(await f(*args, **kwargs))
        except Exception as e:
            return Err(e)

    return wrapper


@dataclass(frozen=True, slots=True)
class Some(Generic[T]):
    """Represents an optional value that exists."""

    value: T

    def is_some(self) -> bool:
        return True

    def is_none(self) -> bool:
        return False

    def unwrap(self) -> T:
        return self.value

    def unwrap_or(self, default: T) -> T:
        return self.value

    def unwrap_or_else(self, f: Callable[[], T]) -> T:
        return self.value

    def map(self, f: Callable[[T], R]) -> Option[R]:
        return Some(f(self.value))

    def filter(self, predicate: Callable[[T], bool]) -> Option[T]:
        return self if predicate(self.value) else Nothing()

    def and_then(self, f: Callable[[T], Option[R]]) -> Option[R]:
        return f(self.value)

    def or_else(self, f: Callable[[], Option[T]]) -> Option[T]:
        return self

    def __bool__(self) -> bool:
        return True


@dataclass(frozen=True, slots=True)
class Nothing(Generic[T]):
    """Represents an optional value that doesn't exist."""

    def is_some(self) -> bool:
        return False

    def is_none(self) -> bool:
        return True

    def unwrap(self) -> Never:
        raise ValueError("Called unwrap on Nothing")

    def unwrap_or(self, default: T) -> T:
        return default

    def unwrap_or_else(self, f: Callable[[], T]) -> T:
        return f()

    def map(self, f: Callable[[T], R]) -> Option[R]:
        return Nothing()

    def filter(self, predicate: Callable[[T], bool]) -> Option[T]:
        return self

    def and_then(self, f: Callable[[T], Option[R]]) -> Option[R]:
        return Nothing()

    def or_else(self, f: Callable[[], Option[T]]) -> Option[T]:
        return f()

    def __bool__(self) -> bool:
        return False


Option: TypeAlias = Some[T] | Nothing[T]


def option_from(value: T | None) -> Option[T]:
    """Create an Option from a nullable value."""
    return Some(value) if value is not None else Nothing()


# =============================================================================
# VALIDATION UTILITIES
# =============================================================================


class Validator(Generic[T], ABC):
    """Abstract base validator."""

    @abstractmethod
    def validate(self, value: T) -> list[str]:
        """Validate value and return list of errors."""
        ...

    def __and__(self, other: Validator[T]) -> CompositeValidator[T]:
        """Combine validators with AND logic."""
        return CompositeValidator([self, other])


class CompositeValidator(Validator[T]):
    """Composite validator that combines multiple validators."""

    def __init__(self, validators: list[Validator[T]]) -> None:
        self.validators = validators

    def validate(self, value: T) -> list[str]:
        errors: list[str] = []
        for validator in self.validators:
            errors.extend(validator.validate(value))
        return errors


class StringValidator(Validator[str]):
    """String validation with multiple rules."""

    def __init__(
        self,
        *,
        min_length: int | None = None,
        max_length: int | None = None,
        pattern: str | None = None,
        not_empty: bool = False,
    ) -> None:
        self.min_length = min_length
        self.max_length = max_length
        self.pattern = re.compile(pattern) if pattern else None
        self.not_empty = not_empty

    def validate(self, value: str) -> list[str]:
        errors: list[str] = []

        if self.not_empty and not value.strip():
            errors.append("Value cannot be empty or whitespace")

        if self.min_length is not None and len(value) < self.min_length:
            errors.append(f"Length must be at least {self.min_length}")

        if self.max_length is not None and len(value) > self.max_length:
            errors.append(f"Length must be at most {self.max_length}")

        if self.pattern is not None and not self.pattern.match(value):
            errors.append(f"Value does not match pattern {self.pattern.pattern}")

        return errors


class EmailValidator(Validator[str]):
    """Email validation."""

    EMAIL_PATTERN = re.compile(
        r"^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$"
    )

    def validate(self, value: str) -> list[str]:
        if not self.EMAIL_PATTERN.match(value):
            return [f"Invalid email format: {value}"]
        return []


class NumberValidator(Validator[int | float]):
    """Numeric validation with range checks."""

    def __init__(
        self,
        *,
        min_value: int | float | None = None,
        max_value: int | float | None = None,
        positive: bool = False,
    ) -> None:
        self.min_value = min_value
        self.max_value = max_value
        self.positive = positive

    def validate(self, value: int | float) -> list[str]:
        errors: list[str] = []

        if self.positive and value <= 0:
            errors.append("Value must be positive")

        if self.min_value is not None and value < self.min_value:
            errors.append(f"Value must be at least {self.min_value}")

        if self.max_value is not None and value > self.max_value:
            errors.append(f"Value must be at most {self.max_value}")

        return errors


class PasswordValidator(Validator[str]):
    """Password strength validation."""

    def __init__(
        self,
        *,
        min_length: int = 8,
        require_uppercase: bool = True,
        require_lowercase: bool = True,
        require_digit: bool = True,
        require_special: bool = True,
    ) -> None:
        self.min_length = min_length
        self.require_uppercase = require_uppercase
        self.require_lowercase = require_lowercase
        self.require_digit = require_digit
        self.require_special = require_special

    def validate(self, value: str) -> list[str]:
        errors: list[str] = []

        if len(value) < self.min_length:
            errors.append(f"Password must be at least {self.min_length} characters")

        if self.require_uppercase and not any(c.isupper() for c in value):
            errors.append("Password must contain at least one uppercase letter")

        if self.require_lowercase and not any(c.islower() for c in value):
            errors.append("Password must contain at least one lowercase letter")

        if self.require_digit and not any(c.isdigit() for c in value):
            errors.append("Password must contain at least one digit")

        if self.require_special:
            special_chars = "!@#$%^&*()_+-=[]{}|;':\",./<>?"
            if not any(c in special_chars for c in value):
                errors.append("Password must contain at least one special character")

        return errors


# =============================================================================
# DOMAIN ENTITIES
# =============================================================================


@dataclass(kw_only=True, slots=True)
class Entity(ABC):
    """Base entity with common fields."""

    id: str = field(default_factory=lambda: str(uuid.uuid4()))
    created_at: datetime = field(default_factory=lambda: datetime.now(timezone.utc))
    updated_at: datetime = field(default_factory=lambda: datetime.now(timezone.utc))
    version: int = 1

    def touch(self) -> Self:
        """Update the updated_at timestamp."""
        return replace(self, updated_at=datetime.now(timezone.utc), version=self.version + 1)


@dataclass(kw_only=True, slots=True)
class User(Entity):
    """User entity with comprehensive validation."""

    username: str
    email: str
    password_hash: str = field(repr=False)
    first_name: str = ""
    last_name: str = ""
    role: UserRole = UserRole.USER
    permissions: Permission = Permission.READ
    is_active: bool = True
    is_verified: bool = False
    last_login: datetime | None = None
    failed_login_attempts: int = 0
    locked_until: datetime | None = None
    metadata: dict[str, Any] = field(default_factory=dict)
    tags: list[str] = field(default_factory=list)

    # Class-level validators
    _username_validator: ClassVar[Validator[str]] = StringValidator(
        min_length=3, max_length=50, pattern=r"^[a-zA-Z0-9_]+$", not_empty=True
    )
    _email_validator: ClassVar[Validator[str]] = EmailValidator()

    def __post_init__(self) -> None:
        """Validate user data after initialization."""
        errors: list[str] = []

        errors.extend(self._username_validator.validate(self.username))
        errors.extend(self._email_validator.validate(self.email))

        if errors:
            raise ValidationError(
                f"User validation failed: {'; '.join(errors)}",
                field="user",
                value={"username": self.username, "email": self.email},
                constraints=errors,
            )

    @property
    def full_name(self) -> str:
        """Get user's full name."""
        parts = [self.first_name, self.last_name]
        return " ".join(p for p in parts if p) or self.username

    @property
    def is_locked(self) -> bool:
        """Check if user account is locked."""
        if self.locked_until is None:
            return False
        return datetime.now(timezone.utc) < self.locked_until

    def has_permission(self, permission: Permission) -> bool:
        """Check if user has specific permission."""
        return bool(self.permissions & permission)

    def is_admin(self) -> bool:
        """Check if user is an admin."""
        return self.role in (UserRole.ADMIN, UserRole.SUPER_ADMIN)

    def record_login(self, success: bool = True) -> Self:
        """Record a login attempt."""
        if success:
            return replace(
                self,
                last_login=datetime.now(timezone.utc),
                failed_login_attempts=0,
                locked_until=None,
            )
        else:
            new_attempts = self.failed_login_attempts + 1
            locked_until = None
            if new_attempts >= 5:
                locked_until = datetime.now(timezone.utc) + timedelta(minutes=15)
            return replace(
                self,
                failed_login_attempts=new_attempts,
                locked_until=locked_until,
            )

    def to_dict(self, include_sensitive: bool = False) -> dict[str, Any]:
        """Convert to dictionary, optionally excluding sensitive fields."""
        data = asdict(self)
        if not include_sensitive:
            data.pop("password_hash", None)
        data["created_at"] = self.created_at.isoformat()
        data["updated_at"] = self.updated_at.isoformat()
        if self.last_login:
            data["last_login"] = self.last_login.isoformat()
        if self.locked_until:
            data["locked_until"] = self.locked_until.isoformat()
        return data


@dataclass(kw_only=True, slots=True)
class Task(Entity):
    """Task entity for task management."""

    title: str
    description: str = ""
    status: Status = Status.PENDING
    priority: Priority = Priority.MEDIUM
    assignee_id: str | None = None
    due_date: datetime | None = None
    completed_at: datetime | None = None
    estimated_hours: float | None = None
    actual_hours: float | None = None
    labels: list[str] = field(default_factory=list)
    parent_id: str | None = None
    subtask_ids: list[str] = field(default_factory=list)

    def __post_init__(self) -> None:
        if not self.title.strip():
            raise ValidationError("Task title cannot be empty", field="title")

    def complete(self) -> Self:
        """Mark task as completed."""
        return replace(
            self,
            status=Status.COMPLETED,
            completed_at=datetime.now(timezone.utc),
        ).touch()

    def is_overdue(self) -> bool:
        """Check if task is overdue."""
        if self.due_date is None or self.status == Status.COMPLETED:
            return False
        return datetime.now(timezone.utc) > self.due_date


@dataclass(kw_only=True, slots=True)
class AuditLog(Entity):
    """Audit log entry for tracking changes."""

    action: str
    entity_type: str
    entity_id: str
    actor_id: str
    old_value: dict[str, Any] | None = None
    new_value: dict[str, Any] | None = None
    ip_address: str | None = None
    user_agent: str | None = None


# =============================================================================
# TYPED DICTIONARIES
# =============================================================================


class UserCreateDTO(TypedDict):
    """Data transfer object for creating a user."""

    username: str
    email: str
    password: str
    first_name: NotRequired[str]
    last_name: NotRequired[str]


class UserUpdateDTO(TypedDict, total=False):
    """Data transfer object for updating a user."""

    first_name: str
    last_name: str
    email: str
    is_active: bool
    metadata: dict[str, Any]


class PaginationParams(TypedDict, total=False):
    """Pagination parameters."""

    page: int
    page_size: int
    sort_by: str
    sort_order: Literal["asc", "desc"]


class PaginatedResponse(TypedDict, Generic[T]):
    """Paginated response wrapper."""

    items: list[T]
    total: int
    page: int
    page_size: int
    total_pages: int
    has_next: bool
    has_prev: bool


# =============================================================================
# PROTOCOLS (STRUCTURAL SUBTYPING)
# =============================================================================


@runtime_checkable
class Identifiable(Protocol):
    """Protocol for entities with an ID."""

    @property
    def id(self) -> str:
        ...


@runtime_checkable
class Timestamped(Protocol):
    """Protocol for entities with timestamps."""

    @property
    def created_at(self) -> datetime:
        ...

    @property
    def updated_at(self) -> datetime:
        ...


class Serializable(Protocol):
    """Protocol for serializable objects."""

    def to_dict(self) -> dict[str, Any]:
        ...


class Repository(Protocol[T]):
    """Repository protocol for data access."""

    async def find_by_id(self, id: str) -> Option[T]:
        """Find entity by ID."""
        ...

    async def find_all(
        self, pagination: PaginationParams | None = None
    ) -> PaginatedResponse[T]:
        """Find all entities with optional pagination."""
        ...

    async def save(self, entity: T) -> T:
        """Save entity."""
        ...

    async def delete(self, id: str) -> bool:
        """Delete entity by ID."""
        ...

    async def exists(self, id: str) -> bool:
        """Check if entity exists."""
        ...

    async def count(self) -> int:
        """Count all entities."""
        ...


class EventHandler(Protocol[T]):
    """Protocol for event handlers."""

    async def handle(self, event: T) -> None:
        """Handle an event."""
        ...


class Middleware(Protocol[T, R]):
    """Protocol for middleware."""

    async def __call__(
        self, request: T, next: Callable[[T], Awaitable[R]]
    ) -> R:
        ...


class PasswordHasher(Protocol):
    """Protocol for password hashing."""

    def hash(self, password: str) -> str:
        ...

    def verify(self, password: str, hash: str) -> bool:
        ...


# =============================================================================
# REPOSITORY IMPLEMENTATIONS
# =============================================================================


class InMemoryRepository(Generic[T]):
