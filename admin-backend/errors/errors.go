// Package errors provides custom error types and error handling utilities.
package errors

import (
	"errors"
	"fmt"
	"net/http"
)

// AppError represents an application error with HTTP status code and wrapped error.
type AppError struct {
	// Code is the HTTP status code to return
	Code int
	// Message is a user-friendly error message
	Message string
	// Err is the underlying error (may be nil)
	Err error
	// Context contains additional error context
	Context map[string]interface{}
}

// Error returns the error message.
func (e *AppError) Error() string {
	if e.Err != nil {
		return fmt.Sprintf("%s: %v", e.Message, e.Err)
	}
	return e.Message
}

// Unwrap returns the underlying error for errors.Is/As.
func (e *AppError) Unwrap() error {
	return e.Err
}

// NewAppError creates a new application error.
func NewAppError(code int, message string, err error) *AppError {
	return &AppError{
		Code:    code,
		Message: message,
		Err:     err,
	}
}

// NewAppErrorWithContext creates a new application error with additional context.
func NewAppErrorWithContext(code int, message string, err error, context map[string]interface{}) *AppError {
	return &AppError{
		Code:    code,
		Message: message,
		Err:     err,
		Context: context,
	}
}

// Common error constructors

// BadRequest creates a 400 Bad Request error.
func BadRequest(message string, err error) *AppError {
	return NewAppError(http.StatusBadRequest, message, err)
}

// Unauthorized creates a 401 Unauthorized error.
func Unauthorized(message string, err error) *AppError {
	return NewAppError(http.StatusUnauthorized, message, err)
}

// Forbidden creates a 403 Forbidden error.
func Forbidden(message string, err error) *AppError {
	return NewAppError(http.StatusForbidden, message, err)
}

// NotFound creates a 404 Not Found error.
func NotFound(message string, err error) *AppError {
	return NewAppError(http.StatusNotFound, message, err)
}

// Conflict creates a 409 Conflict error.
func Conflict(message string, err error) *AppError {
	return NewAppError(http.StatusConflict, message, err)
}

// InternalServerError creates a 500 Internal Server Error.
func InternalServerError(message string, err error) *AppError {
	return NewAppError(http.StatusInternalServerError, message, err)
}

// ServiceUnavailable creates a 503 Service Unavailable error.
func ServiceUnavailable(message string, err error) *AppError {
	return NewAppError(http.StatusServiceUnavailable, message, err)
}

// Wrap wraps an error with additional context.
func Wrap(err error, message string) error {
	if err == nil {
		return nil
	}
	return fmt.Errorf("%s: %w", message, err)
}

// Is checks if err is target.
func Is(err, target error) bool {
	return errors.Is(err, target)
}

// As checks if err can be cast to target.
func As(err error, target interface{}) bool {
	return errors.As(err, target)
}

// Join joins multiple errors into one.
func Join(errs ...error) error {
	return errors.Join(errs...)
}
