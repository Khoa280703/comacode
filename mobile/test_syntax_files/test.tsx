// React TSX sample file - Modern patterns
import React, {
  useState,
  useEffect,
  useCallback,
  useMemo,
  useRef,
  createContext,
  useContext,
  Suspense,
  lazy
} from 'react';

// Types and interfaces
interface User {
  id: string;
  name: string;
  email: string;
  avatar?: string;
  role: 'admin' | 'user' | 'guest';
}

interface ThemeContextValue {
  theme: 'light' | 'dark';
  toggleTheme: () => void;
  colors: {
    primary: string;
    secondary: string;
    background: string;
    text: string;
  };
}

// Props with generics
interface DataTableProps<T> {
  data: T[];
  columns: ColumnDefinition<T>[];
  onRowClick?: (row: T) => void;
  loading?: boolean;
  emptyMessage?: string;
}

interface ColumnDefinition<T> {
  key: keyof T;
  header: string;
  render?: (value: T[keyof T], row: T) => React.ReactNode;
  sortable?: boolean;
  width?: string | number;
}

// Context creation
const ThemeContext = createContext<ThemeContextValue | null>(null);

// Custom hooks
function useTheme(): ThemeContextValue {
  const context = useContext(ThemeContext);
  if (!context) {
    throw new Error('useTheme must be used within ThemeProvider');
  }
  return context;
}

function useDebounce<T>(value: T, delay: number): T {
  const [debouncedValue, setDebouncedValue] = useState(value);

  useEffect(() => {
    const timer = setTimeout(() => setDebouncedValue(value), delay);
    return () => clearTimeout(timer);
  }, [value, delay]);

  return debouncedValue;
}

function useFetch<T>(url: string): {
  data: T | null;
  loading: boolean;
  error: Error | null;
  refetch: () => void;
} {
  const [data, setData] = useState<T | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<Error | null>(null);

  const fetchData = useCallback(async () => {
    setLoading(true);
    setError(null);

    try {
      const response = await fetch(url);
      if (!response.ok) {
        throw new Error(`HTTP error! status: ${response.status}`);
      }
      const json = await response.json();
      setData(json);
    } catch (e) {
      setError(e instanceof Error ? e : new Error('Unknown error'));
    } finally {
      setLoading(false);
    }
  }, [url]);

  useEffect(() => {
    fetchData();
  }, [fetchData]);

  return { data, loading, error, refetch: fetchData };
}

// Generic DataTable component
function DataTable<T extends { id: string }>({
  data,
  columns,
  onRowClick,
  loading = false,
  emptyMessage = 'No data available',
}: DataTableProps<T>): JSX.Element {
  const [sortColumn, setSortColumn] = useState<keyof T | null>(null);
  const [sortDirection, setSortDirection] = useState<'asc' | 'desc'>('asc');

  const sortedData = useMemo(() => {
    if (!sortColumn) return data;

    return [...data].sort((a, b) => {
      const aValue = a[sortColumn];
      const bValue = b[sortColumn];

      if (aValue < bValue) return sortDirection === 'asc' ? -1 : 1;
      if (aValue > bValue) return sortDirection === 'asc' ? 1 : -1;
      return 0;
    });
  }, [data, sortColumn, sortDirection]);

  const handleSort = (column: keyof T) => {
    if (sortColumn === column) {
      setSortDirection(prev => prev === 'asc' ? 'desc' : 'asc');
    } else {
      setSortColumn(column);
      setSortDirection('asc');
    }
  };

  if (loading) {
    return (
      <div className="table-loading">
        <div className="spinner" />
        <span>Loading...</span>
      </div>
    );
  }

  if (sortedData.length === 0) {
    return <div className="table-empty">{emptyMessage}</div>;
  }

  return (
    <table className="data-table">
      <thead>
        <tr>
          {columns.map((col) => (
            <th
              key={String(col.key)}
              onClick={() => col.sortable && handleSort(col.key)}
              style={{ width: col.width, cursor: col.sortable ? 'pointer' : 'default' }}
            >
              {col.header}
              {sortColumn === col.key && (
                <span>{sortDirection === 'asc' ? ' ▲' : ' ▼'}</span>
              )}
            </th>
          ))}
        </tr>
      </thead>
      <tbody>
        {sortedData.map((row) => (
          <tr key={row.id} onClick={() => onRowClick?.(row)}>
            {columns.map((col) => (
              <td key={String(col.key)}>
                {col.render
                  ? col.render(row[col.key], row)
                  : String(row[col.key])}
              </td>
            ))}
          </tr>
        ))}
      </tbody>
    </table>
  );
}

// ============================================================================
// Theme Provider Component
// ============================================================================

const lightColors = {
  primary: '#3b82f6',
  secondary: '#8b5cf6',
  background: '#ffffff',
  text: '#1f2937',
};

const darkColors = {
  primary: '#60a5fa',
  secondary: '#a78bfa',
  background: '#111827',
  text: '#f9fafb',
};

function ThemeProvider({ children }: { children: React.ReactNode }) {
  const [theme, setTheme] = useState<'light' | 'dark'>('light');

  const value = useMemo<ThemeContextValue>(() => ({
    theme,
    toggleTheme: () => setTheme(prev => prev === 'light' ? 'dark' : 'light'),
    colors: theme === 'light' ? lightColors : darkColors,
  }), [theme]);

  return (
    <ThemeContext.Provider value={value}>
      <div
        style={{
          backgroundColor: value.colors.background,
          color: value.colors.text,
          minHeight: '100vh',
          transition: 'all 0.3s ease',
        }}
      >
        {children}
      </div>
    </ThemeContext.Provider>
  );
}

// ============================================================================
// Form Components with Validation
// ============================================================================

type ValidationRule<T> = {
  validate: (value: T) => boolean;
  message: string;
};

interface FormFieldProps<T> {
  label: string;
  value: T;
  onChange: (value: T) => void;
  rules?: ValidationRule<T>[];
  required?: boolean;
  disabled?: boolean;
}

function useFormValidation<T extends Record<string, unknown>>(
  initialValues: T,
  rules: Partial<Record<keyof T, ValidationRule<T[keyof T]>[]>>
) {
  const [values, setValues] = useState<T>(initialValues);
  const [errors, setErrors] = useState<Partial<Record<keyof T, string[]>>>({});
  const [touched, setTouched] = useState<Partial<Record<keyof T, boolean>>>({});

  const validate = useCallback((field: keyof T, value: T[keyof T]): string[] => {
    const fieldRules = rules[field] ?? [];
    return fieldRules
      .filter(rule => !rule.validate(value))
      .map(rule => rule.message);
  }, [rules]);

  const setValue = useCallback(<K extends keyof T>(field: K, value: T[K]) => {
    setValues(prev => ({ ...prev, [field]: value }));
    setTouched(prev => ({ ...prev, [field]: true }));
    const fieldErrors = validate(field, value);
    setErrors(prev => ({ ...prev, [field]: fieldErrors }));
  }, [validate]);

  const isValid = useMemo(() =>
    Object.values(errors).every((errs) =>
      (errs as string[]).length === 0
    ),
  [errors]);

  const validateAll = useCallback((): boolean => {
    const allErrors: Partial<Record<keyof T, string[]>> = {};
    let hasErrors = false;

    for (const field of Object.keys(values) as Array<keyof T>) {
      const fieldErrors = validate(field, values[field]);
      if (fieldErrors.length > 0) {
        allErrors[field] = fieldErrors;
        hasErrors = true;
      }
    }

    setErrors(allErrors);
    setTouched(Object.fromEntries(
      Object.keys(values).map(k => [k, true])
    ) as Partial<Record<keyof T, boolean>>);

    return !hasErrors;
  }, [values, validate]);

  return { values, errors, touched, setValue, isValid, validateAll };
}

interface TextInputProps extends Omit<FormFieldProps<string>, 'onChange'> {
  type?: 'text' | 'email' | 'password' | 'url';
  placeholder?: string;
  onChange: (value: string) => void;
}

function TextInput({
  label,
  value,
  onChange,
  type = 'text',
  placeholder,
  rules = [],
  required = false,
  disabled = false,
}: TextInputProps) {
  const [isFocused, setIsFocused] = useState(false);
  const [errors, setErrors] = useState<string[]>([]);
  const inputRef = useRef<HTMLInputElement>(null);

  const handleBlur = () => {
    setIsFocused(false);
    const validationErrors = rules
      .filter(rule => !rule.validate(value))
      .map(rule => rule.message);
    if (required && !value) {
      validationErrors.unshift(`${label} is required`);
    }
    setErrors(validationErrors);
  };

  return (
    <div className={`form-field ${errors.length > 0 ? 'has-error' : ''}`}>
      <label htmlFor={label.toLowerCase().replace(/\s+/g, '-')}>
        {label}
        {required && <span className="required-marker">*</span>}
      </label>
      <input
        ref={inputRef}
        id={label.toLowerCase().replace(/\s+/g, '-')}
        type={type}
        value={value}
        onChange={e => onChange(e.target.value)}
        onFocus={() => setIsFocused(true)}
        onBlur={handleBlur}
        placeholder={placeholder}
        disabled={disabled}
        className={isFocused ? 'focused' : ''}
        aria-invalid={errors.length > 0}
        aria-describedby={errors.length > 0 ? `${label}-errors` : undefined}
      />
      {errors.length > 0 && (
        <ul id={`${label}-errors`} className="field-errors" role="alert">
          {errors.map((err, i) => (
            <li key={i}>{err}</li>
          ))}
        </ul>
      )}
    </div>
  );
}

// ============================================================================
// Modal Component
// ============================================================================

interface ModalProps {
  isOpen: boolean;
  onClose: () => void;
  title: string;
  children: React.ReactNode;
  footer?: React.ReactNode;
  size?: 'small' | 'medium' | 'large';
  closeOnOverlay?: boolean;
}

function Modal({
  isOpen,
  onClose,
  title,
  children,
  footer,
  size = 'medium',
  closeOnOverlay = true,
}: ModalProps) {
  const modalRef = useRef<HTMLDivElement>(null);

  useEffect(() => {
    if (isOpen) {
      document.body.style.overflow = 'hidden';
      modalRef.current?.focus();
    }
    return () => {
      document.body.style.overflow = '';
    };
  }, [isOpen]);

  useEffect(() => {
    const handleEscape = (e: KeyboardEvent) => {
      if (e.key === 'Escape' && isOpen) onClose();
    };
    document.addEventListener('keydown', handleEscape);
    return () => document.removeEventListener('keydown', handleEscape);
  }, [isOpen, onClose]);

  if (!isOpen) return null;

  const sizeClasses: Record<string, string> = {
    small: 'max-w-sm',
    medium: 'max-w-lg',
    large: 'max-w-4xl',
  };

  return (
    <div
      className="modal-overlay"
      onClick={closeOnOverlay ? onClose : undefined}
      role="dialog"
      aria-modal="true"
      aria-labelledby="modal-title"
    >
      <div
        ref={modalRef}
        className={`modal-content ${sizeClasses[size]}`}
        onClick={e => e.stopPropagation()}
        tabIndex={-1}
      >
        <div className="modal-header">
          <h2 id="modal-title">{title}</h2>
          <button
            className="modal-close"
            onClick={onClose}
            aria-label="Close modal"
          >
            ×
          </button>
        </div>
        <div className="modal-body">{children}</div>
        {footer && <div className="modal-footer">{footer}</div>}
      </div>
    </div>
  );
}

// ============================================================================
// Notification System
// ============================================================================

type NotificationType = 'success' | 'error' | 'warning' | 'info';

interface Notification {
  id: string;
  type: NotificationType;
  title: string;
  message?: string;
  duration?: number;
  dismissible?: boolean;
}

interface NotificationContextValue {
  notifications: Notification[];
  addNotification: (notification: Omit<Notification, 'id'>) => void;
  removeNotification: (id: string) => void;
  clearAll: () => void;
}

const NotificationContext = createContext<NotificationContextValue | null>(null);

function useNotifications() {
  const context = useContext(NotificationContext);
  if (!context) throw new Error('useNotifications must be used within NotificationProvider');
  return context;
}

function NotificationProvider({ children }: { children: React.ReactNode }) {
  const [notifications, setNotifications] = useState<Notification[]>([]);

  const addNotification = useCallback((notification: Omit<Notification, 'id'>) => {
    const id = crypto.randomUUID();
    const newNotification: Notification = { ...notification, id };
    setNotifications(prev => [...prev, newNotification]);

    if (notification.duration !== 0) {
      setTimeout(() => {
        setNotifications(prev => prev.filter(n => n.id !== id));
      }, notification.duration ?? 5000);
    }
  }, []);

  const removeNotification = useCallback((id: string) => {
    setNotifications(prev => prev.filter(n => n.id !== id));
  }, []);

  const clearAll = useCallback(() => setNotifications([]), []);

  return (
    <NotificationContext.Provider value={{ notifications, addNotification, removeNotification, clearAll }}>
      {children}
      <NotificationContainer notifications={notifications} onDismiss={removeNotification} />
    </NotificationContext.Provider>
  );
}

function NotificationContainer({
  notifications,
  onDismiss,
}: {
  notifications: Notification[];
  onDismiss: (id: string) => void;
}) {
  const iconMap: Record<NotificationType, string> = {
    success: '✓',
    error: '✕',
    warning: '⚠',
    info: 'ℹ',
  };

  return (
    <div className="notification-container" aria-live="polite">
      {notifications.map(notification => (
        <div
          key={notification.id}
          className={`notification notification-${notification.type}`}
          role="alert"
        >
          <span className="notification-icon">{iconMap[notification.type]}</span>
          <div className="notification-content">
            <strong>{notification.title}</strong>
            {notification.message && <p>{notification.message}</p>}
          </div>
          {notification.dismissible !== false && (
            <button
              className="notification-dismiss"
              onClick={() => onDismiss(notification.id)}
              aria-label="Dismiss notification"
            >
              ×
            </button>
          )}
        </div>
      ))}
    </div>
  );
}

// ============================================================================
// Pagination Component
// ============================================================================

interface PaginationProps {
  currentPage: number;
  totalPages: number;
  onPageChange: (page: number) => void;
  siblingCount?: number;
}

function Pagination({
  currentPage,
  totalPages,
  onPageChange,
  siblingCount = 1,
}: PaginationProps) {
  const range = useMemo(() => {
    const totalPageNumbers = siblingCount + 5;

    if (totalPageNumbers >= totalPages) {
      return Array.from({ length: totalPages }, (_, i) => i + 1);
    }

    const leftSiblingIndex = Math.max(currentPage - siblingCount, 1);
    const rightSiblingIndex = Math.min(currentPage + siblingCount, totalPages);

    const shouldShowLeftDots = leftSiblingIndex > 2;
    const shouldShowRightDots = rightSiblingIndex < totalPages - 2;

    if (!shouldShowLeftDots && shouldShowRightDots) {
      const leftRange = Array.from({ length: 3 + 2 * siblingCount }, (_, i) => i + 1);
      return [...leftRange, '...', totalPages];
    }

    if (shouldShowLeftDots && !shouldShowRightDots) {
      const rightRange = Array.from(
        { length: 3 + 2 * siblingCount },
        (_, i) => totalPages - (3 + 2 * siblingCount) + i + 1
      );
      return [1, '...', ...rightRange];
    }

    const middleRange = Array.from(
      { length: rightSiblingIndex - leftSiblingIndex + 1 },
      (_, i) => leftSiblingIndex + i
    );
    return [1, '...', ...middleRange, '...', totalPages];
  }, [currentPage, totalPages, siblingCount]);

  return (
    <nav aria-label="Pagination" className="pagination">
      <button
        disabled={currentPage === 1}
        onClick={() => onPageChange(currentPage - 1)}
        aria-label="Previous page"
      >
        ← Previous
      </button>

      {range.map((page, index) =>
        typeof page === 'string' ? (
          <span key={`dots-${index}`} className="pagination-dots">
            {page}
          </span>
        ) : (
          <button
            key={page}
            onClick={() => onPageChange(page)}
            className={currentPage === page ? 'active' : ''}
            aria-current={currentPage === page ? 'page' : undefined}
          >
            {page}
          </button>
        )
      )}

      <button
        disabled={currentPage === totalPages}
        onClick={() => onPageChange(currentPage + 1)}
        aria-label="Next page"
      >
        Next →
      </button>
    </nav>
  );
}

// ============================================================================
// Virtualized List Component
// ============================================================================

interface VirtualListProps<T> {
  items: T[];
  itemHeight: number;
  containerHeight: number;
  renderItem: (item: T, index: number) => React.ReactNode;
  overscan?: number;
}

function VirtualList<T>({
  items,
  itemHeight,
  containerHeight,
  renderItem,
  overscan = 3,
}: VirtualListProps<T>) {
  const [scrollTop, setScrollTop] = useState(0);
  const containerRef = useRef<HTMLDivElement>(null);

  const totalHeight = items.length * itemHeight;
  const startIndex = Math.max(0, Math.floor(scrollTop / itemHeight) - overscan);
  const endIndex = Math.min(
    items.length - 1,
    Math.ceil((scrollTop + containerHeight) / itemHeight) + overscan
  );

  const visibleItems = useMemo(() => {
    const result: { item: T; index: number; offset: number }[] = [];
    for (let i = startIndex; i <= endIndex; i++) {
      result.push({ item: items[i], index: i, offset: i * itemHeight });
    }
    return result;
  }, [items, startIndex, endIndex, itemHeight]);

  return (
    <div
      ref={containerRef}
      className="virtual-list-container"
      style={{ height: containerHeight, overflow: 'auto' }}
      onScroll={e => setScrollTop(e.currentTarget.scrollTop)}
    >
      <div style={{ height: totalHeight, position: 'relative' }}>
        {visibleItems.map(({ item, index, offset }) => (
          <div
            key={index}
            style={{
              position: 'absolute',
              top: offset,
              height: itemHeight,
              width: '100%',
            }}
          >
            {renderItem(item, index)}
          </div>
        ))}
      </div>
    </div>
  );
}

// ============================================================================
// Higher-Order Component (HOC) Pattern
// ============================================================================

type WithLoadingProps = {
  loading: boolean;
};

function withLoading<P extends object>(
  WrappedComponent: React.ComponentType<P>
): React.FC<P & WithLoadingProps> {
  const WithLoadingComponent: React.FC<P & WithLoadingProps> = ({
    loading,
    ...props
  }) => {
    if (loading) {
      return (
        <div className="loading-overlay">
          <div className="loading-spinner" />
          <p>Loading...</p>
        </div>
      );
    }
    return <WrappedComponent {...(props as P)} />;
  };

  WithLoadingComponent.displayName = `WithLoading(${
    WrappedComponent.displayName || WrappedComponent.name || 'Component'
  })`;

  return WithLoadingComponent;
}

// ============================================================================
// Utility Types and Helpers
// ============================================================================

type DeepPartial<T> = {
  [P in keyof T]?: T[P] extends object ? DeepPartial<T[P]> : T[P];
};

type DeepReadonly<T> = {
  readonly [P in keyof T]: T[P] extends object ? DeepReadonly<T[P]> : T[P];
};

type Nullable<T> = { [P in keyof T]: T[P] | null };

type RequiredKeys<T, K extends keyof T> = Omit<T, K> & Required<Pick<T, K>>;

function assertNever(value: never): never {
  throw new Error(`Unexpected value: ${value}`);
}

function isNonNullable<T>(value: T): value is NonNullable<T> {
  return value !== null && value !== undefined;
}

function groupBy<T, K extends string | number>(
  items: T[],
  keyFn: (item: T) => K
): Record<K, T[]> {
  return items.reduce((acc, item) => {
    const key = keyFn(item);
    (acc[key] ??= []).push(item);
    return acc;
  }, {} as Record<K, T[]>);
}

function debounce<T extends (...args: unknown[]) => unknown>(
  fn: T,
  delay: number
): (...args: Parameters<T>) => void {
  let timeoutId: ReturnType<typeof setTimeout>;
  return (...args: Parameters<T>) => {
    clearTimeout(timeoutId);
    timeoutId = setTimeout(() => fn(...args), delay);
  };
}

function throttle<T extends (...args: unknown[]) => unknown>(
  fn: T,
  limit: number
): (...args: Parameters<T>) => void {
  let inThrottle = false;
  return (...args: Parameters<T>) => {
    if (!inThrottle) {
      fn(...args);
      inThrottle = true;
      setTimeout(() => { inThrottle = false; }, limit);
    }
  };
}

// ============================================================================
// Lazy-loaded Components
// ============================================================================

const LazyDashboard = lazy(() => import('./Dashboard'));
const LazySettings = lazy(() => import('./Settings'));
const LazyAnalytics = lazy(() => import('./Analytics'));

// ============================================================================
// App Component
// ============================================================================

function App() {
  const [currentRoute, setCurrentRoute] = useState<'home' | 'dashboard' | 'settings'>('home');
  const [modalOpen, setModalOpen] = useState(false);
  const [users] = useState<User[]>([
    { id: '1', name: 'Alice Johnson', email: 'alice@example.com', role: 'admin' },
    { id: '2', name: 'Bob Smith', email: 'bob@example.com', role: 'user' },
    { id: '3', name: 'Charlie Brown', email: 'charlie@example.com', role: 'guest' },
  ]);

  const columns: ColumnDefinition<User>[] = useMemo(() => [
    { key: 'name', header: 'Name', sortable: true },
    { key: 'email', header: 'Email', sortable: true },
    {
      key: 'role',
      header: 'Role',
      sortable: true,
      render: (value) => (
        <span className={`badge badge-${value}`}>
          {String(value).toUpperCase()}
        </span>
      ),
    },
  ], []);

  return (
    <ThemeProvider>
      <NotificationProvider>
        <div className="app">
          <header className="app-header">
            <h1>React TSX Syntax Demo</h1>
            <nav>
              <button onClick={() => setCurrentRoute('home')}>Home</button>
              <button onClick={() => setCurrentRoute('dashboard')}>Dashboard</button>
              <button onClick={() => setCurrentRoute('settings')}>Settings</button>
            </nav>
            <ThemeToggle />
          </header>

          <main className="app-main">
            {currentRoute === 'home' && (
              <>
                <h2>User Directory</h2>
                <DataTable
                  data={users}
                  columns={columns}
                  onRowClick={(user) => console.log('Clicked:', user)}
                />
                <button onClick={() => setModalOpen(true)}>
                  Open Modal
                </button>
                <Pagination
                  currentPage={1}
                  totalPages={10}
                  onPageChange={(page) => console.log('Page:', page)}
                />
              </>
            )}

            {currentRoute === 'dashboard' && (
              <Suspense fallback={<div>Loading dashboard...</div>}>
                <LazyDashboard />
              </Suspense>
            )}

            {currentRoute === 'settings' && (
              <Suspense fallback={<div>Loading settings...</div>}>
                <LazySettings />
              </Suspense>
            )}
          </main>

          <Modal
            isOpen={modalOpen}
            onClose={() => setModalOpen(false)}
            title="User Details"
            size="medium"
            footer={
              <div className="modal-actions">
                <button onClick={() => setModalOpen(false)}>Cancel</button>
                <button className="primary" onClick={() => setModalOpen(false)}>
                  Save
                </button>
              </div>
            }
          >
            <TextInput
              label="Name"
              value=""
              onChange={(val) => console.log(val)}
              required
              rules={[
                { validate: v => v.length >= 2, message: 'Name must be at least 2 characters' },
                { validate: v => v.length <= 100, message: 'Name must be 100 characters or less' },
              ]}
            />
            <TextInput
              label="Email"
              value=""
              type="email"
              onChange={(val) => console.log(val)}
              required
              rules={[
                { validate: v => /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(v), message: 'Invalid email' },
              ]}
            />
          </Modal>
        </div>
      </NotificationProvider>
    </ThemeProvider>
  );
}

function ThemeToggle() {
  const { theme, toggleTheme } = useTheme();
  return (
    <button onClick={toggleTheme} aria-label={`Switch to ${theme === 'light' ? 'dark' : 'light'} mode`}>
      {theme === 'light' ? '🌙' : '☀️'}
    </button>
  );
}

export default App;
export { DataTable, Modal, TextInput, Pagination, VirtualList, ThemeProvider, NotificationProvider };
export type { User, DataTableProps, ColumnDefinition, ModalProps, NotificationType };

