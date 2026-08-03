// Package store owns the agentd SQLite ledger. The daemon is the single
// writer; other processes read the database file directly (WAL journal mode
// keeps readers and the writer from blocking each other).
package store

import (
	"database/sql"
	"embed"
	"os"
	"path/filepath"
	"time"

	"github.com/pressly/goose/v3"
	_ "modernc.org/sqlite"
)

//go:embed migrations/*.sql
var migrations embed.FS

// Open opens (creating if needed) the ledger at path in WAL mode and runs any
// pending goose migrations. Safe to call on an existing database.
func Open(path string) (*Store, error) {
	if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
		return nil, err
	}
	db, err := sql.Open("sqlite",
		"file:"+path+"?_pragma=journal_mode(WAL)&_pragma=busy_timeout(5000)&_pragma=foreign_keys(1)")
	if err != nil {
		return nil, err
	}
	goose.SetBaseFS(migrations)
	goose.SetLogger(goose.NopLogger())
	if err := goose.SetDialect("sqlite3"); err != nil {
		_ = db.Close()
		return nil, err
	}
	if err := goose.Up(db, "migrations"); err != nil {
		_ = db.Close()
		return nil, err
	}
	return &Store{db: db, now: time.Now}, nil
}

type Store struct {
	db  *sql.DB
	now func() time.Time
}

func (s *Store) Close() error { return s.db.Close() }

// SetNow overrides the clock. Test seam.
func (s *Store) SetNow(fn func() time.Time) { s.now = fn }
