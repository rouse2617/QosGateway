// Package logger provides structured logging functionality using zap.
package logger

import (
	"os"

	"go.uber.org/zap"
	"go.uber.org/zap/zapcore"
)

var (
	// globalLogger is the default global logger instance
	globalLogger *Logger
)

// Logger wraps zap.SugaredLogger for structured logging.
type Logger struct {
	sugar *zap.SugaredLogger
}

// NewLogger creates a new logger with the specified configuration.
// level is the minimum log level (debug, info, warn, error).
// format is the log format (json or console).
// outputPath is the file path for log output (empty string for stdout).
func NewLogger(level string, format string, outputPath string) (*Logger, error) {
	// Parse log level
	var zapLevel zapcore.Level
	if err := zapLevel.UnmarshalText([]byte(level)); err != nil {
		return nil, err
	}

	// Configure encoder
	var encoderConfig zapcore.EncoderConfig
	if format == "json" {
		encoderConfig = zapcore.EncoderConfig{
			TimeKey:        "timestamp",
			LevelKey:       "level",
			NameKey:        "logger",
			CallerKey:      "caller",
			FunctionKey:    zapcore.OmitKey,
			MessageKey:     "message",
			StacktraceKey:  "stacktrace",
			LineEnding:     zapcore.DefaultLineEnding,
			EncodeLevel:    zapcore.LowercaseLevelEncoder,
			EncodeTime:     zapcore.ISO8601TimeEncoder,
			EncodeDuration: zapcore.SecondsDurationEncoder,
			EncodeCaller:   zapcore.ShortCallerEncoder,
		}
	} else {
		// Console format with colors
		encoderConfig = zapcore.EncoderConfig{
			TimeKey:        "T",
			LevelKey:       "L",
			NameKey:        "N",
			CallerKey:      "C",
			FunctionKey:    zapcore.OmitKey,
			MessageKey:     "M",
			StacktraceKey:  "S",
			LineEnding:     zapcore.DefaultLineEnding,
			EncodeLevel:    zapcore.CapitalColorLevelEncoder,
			EncodeTime:     zapcore.ISO8601TimeEncoder,
			EncodeDuration: zapcore.StringDurationEncoder,
			EncodeCaller:   zapcore.ShortCallerEncoder,
		}
	}

	// Configure output
	var writeSync zapcore.WriteSyncer
	if outputPath != "" {
		file, err := os.OpenFile(outputPath, os.O_APPEND|os.O_CREATE|os.O_WRONLY, 0644)
		if err != nil {
			return nil, err
		}
		writeSync = zapcore.AddSync(file)
	} else {
		writeSync = zapcore.AddSync(os.Stdout)
	}

	// Build encoder
	var encoder zapcore.Encoder
	if format == "json" {
		encoder = zapcore.NewJSONEncoder(encoderConfig)
	} else {
		encoder = zapcore.NewConsoleEncoder(encoderConfig)
	}

	// Create core
	core := zapcore.NewCore(encoder, writeSync, zapLevel)

	// Create logger
	zapLogger := zap.New(core, zap.AddCaller(), zap.AddStacktrace(zapcore.ErrorLevel))
	sugar := zapLogger.Sugar()

	return &Logger{sugar: sugar}, nil
}

// Init initializes the global logger with the specified configuration.
func Init(level string, format string, outputPath string) error {
	logger, err := NewLogger(level, format, outputPath)
	if err != nil {
		return err
	}
	globalLogger = logger
	return nil
}

// Get returns the global logger instance.
// If not initialized, it creates a default logger.
func Get() *Logger {
	if globalLogger == nil {
		logger, _ := NewLogger("info", "console", "")
		globalLogger = logger
	}
	return globalLogger
}

// With creates a child logger with additional fields.
func (l *Logger) With(args ...interface{}) *Logger {
	return &Logger{sugar: l.sugar.With(args...)}
}

// Debug logs a debug message.
func (l *Logger) Debug(msg string, args ...interface{}) {
	l.sugar.Debugf(msg, args...)
}

// Debugw logs a debug message with structured context.
func (l *Logger) Debugw(msg string, keysAndValues ...interface{}) {
	l.sugar.Debugw(msg, keysAndValues...)
}

// Info logs an info message.
func (l *Logger) Info(msg string, args ...interface{}) {
	l.sugar.Infof(msg, args...)
}

// Infow logs an info message with structured context.
func (l *Logger) Infow(msg string, keysAndValues ...interface{}) {
	l.sugar.Infow(msg, keysAndValues...)
}

// Warn logs a warning message.
func (l *Logger) Warn(msg string, args ...interface{}) {
	l.sugar.Warnf(msg, args...)
}

// Warnw logs a warning message with structured context.
func (l *Logger) Warnw(msg string, keysAndValues ...interface{}) {
	l.sugar.Warnw(msg, keysAndValues...)
}

// Error logs an error message.
func (l *Logger) Error(msg string, args ...interface{}) {
	l.sugar.Errorf(msg, args...)
}

// Errorw logs an error message with structured context.
func (l *Logger) Errorw(msg string, keysAndValues ...interface{}) {
	l.sugar.Errorw(msg, keysAndValues...)
}

// Fatal logs a fatal message and exits the application.
func (l *Logger) Fatal(msg string, args ...interface{}) {
	l.sugar.Fatalf(msg, args...)
}

// Fatalw logs a fatal message with structured context and exits.
func (l *Logger) Fatalw(msg string, keysAndValues ...interface{}) {
	l.sugar.Fatalw(msg, keysAndValues...)
}

// Sync flushes any buffered log entries.
func (l *Logger) Sync() error {
	return l.sugar.Sync()
}

// Global logger convenience functions

// Debug logs a debug message using the global logger.
func Debug(msg string, args ...interface{}) {
	Get().Debug(msg, args...)
}

// Infow logs an info message with structured context using the global logger.
func Infow(msg string, keysAndValues ...interface{}) {
	Get().Infow(msg, keysAndValues...)
}

// Info logs an info message using the global logger.
func Info(msg string, args ...interface{}) {
	Get().Info(msg, args...)
}

// Warnw logs a warning message with structured context using the global logger.
func Warnw(msg string, keysAndValues ...interface{}) {
	Get().Warnw(msg, keysAndValues...)
}

// Warn logs a warning message using the global logger.
func Warn(msg string, args ...interface{}) {
	Get().Warn(msg, args...)
}

// Errorw logs an error message with structured context using the global logger.
func Errorw(msg string, keysAndValues ...interface{}) {
	Get().Errorw(msg, keysAndValues...)
}

// Error logs an error message using the global logger.
func Error(msg string, args ...interface{}) {
	Get().Error(msg, args...)
}

// Fatalw logs a fatal message with structured context using the global logger and exits.
func Fatalw(msg string, keysAndValues ...interface{}) {
	Get().Fatalw(msg, keysAndValues...)
}

// Fatal logs a fatal message using the global logger and exits.
func Fatal(msg string, args ...interface{}) {
	Get().Fatal(msg, args...)
}

// Sync flushes any buffered log entries in the global logger.
func Sync() error {
	return Get().Sync()
}
