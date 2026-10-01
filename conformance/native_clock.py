"""Control SQLite's engine clock without rewriting SQL, defaults or triggers."""

import ctypes as c
from uuid import uuid4


class Vfs(c.Structure):
    """sqlite3_vfs ABI from the pinned sqlite3.h, through structure version three."""

    _fields_ = [(name, c.c_int) for name in ("iVersion", "szOsFile", "mxPathname")] + [
        (name, c.c_void_p) for name in (
            "pNext", "zName", "pAppData", "xOpen", "xDelete", "xAccess",
            "xFullPathname", "xDlOpen", "xDlError", "xDlSym", "xDlClose",
            "xRandomness", "xSleep", "xCurrentTime", "xGetLastError",
            "xCurrentTimeInt64", "xSetSystemCall", "xGetSystemCall", "xNextSystemCall")]


class NativeClock:
    """A private VFS retaining the native filesystem and supplying Unix milliseconds.

    Connections opened with this name must close before unregistering the VFS.
    The default VFS is never replaced; callbacks remain alive with this object.
    """

    def __init__(self, library: c.CDLL, unix_milliseconds: int) -> None:
        self.library = library
        self.set_time(unix_milliseconds)
        library.sqlite3_vfs_find.argtypes = [c.c_char_p]
        library.sqlite3_vfs_find.restype = c.POINTER(Vfs)
        library.sqlite3_vfs_register.argtypes = [c.POINTER(Vfs), c.c_int]
        library.sqlite3_vfs_register.restype = c.c_int
        library.sqlite3_vfs_unregister.argtypes = [c.POINTER(Vfs)]
        library.sqlite3_vfs_unregister.restype = c.c_int
        original = library.sqlite3_vfs_find(None)
        if not original or original.contents.iVersion not in (2, 3):
            raise RuntimeError("Controlled clock requires a SQLite VFS version 2 or 3")
        self.vfs = Vfs()
        c.memmove(c.byref(self.vfs), original, c.sizeof(Vfs))
        self.name = ("conformance-clock-" + uuid4().hex).encode()
        self.vfs.zName = c.cast(c.c_char_p(self.name), c.c_void_p).value
        self.vfs.pNext = None
        self.current_time = c.CFUNCTYPE(c.c_int, c.c_void_p, c.POINTER(c.c_double))(self._days)
        self.current_time_int64 = c.CFUNCTYPE(c.c_int, c.c_void_p, c.POINTER(c.c_int64))(self._milliseconds)
        self.vfs.xCurrentTime = c.cast(self.current_time, c.c_void_p).value
        self.vfs.xCurrentTimeInt64 = c.cast(self.current_time_int64, c.c_void_p).value
        if library.sqlite3_vfs_register(c.byref(self.vfs), 0):
            raise RuntimeError("Could not register controlled SQLite clock")
        self.registered = True

    def set_time(self, unix_milliseconds: int) -> None:
        """Validate SQLite's supported date range before a callback can expose it."""
        if type(unix_milliseconds) is not int or not -210866760000000 <= unix_milliseconds < 253402300800000:
            raise ValueError("Clock must be Unix milliseconds in SQLite's date range")
        self.julian_milliseconds = unix_milliseconds + 210866760000000

    def _days(self, _vfs: int, destination: c.POINTER(c.c_double)) -> int:
        """Supply the version-one fallback in Julian days."""
        destination[0] = self.julian_milliseconds / 86400000
        return 0

    def _milliseconds(self, _vfs: int, destination: c.POINTER(c.c_int64)) -> int:
        """Supply the engine's preferred integer Julian-millisecond callback."""
        destination[0] = self.julian_milliseconds
        return 0

    def close(self) -> None:
        """Unregister only after all connections using this clock have closed."""
        if self.registered:
            if self.library.sqlite3_vfs_unregister(c.byref(self.vfs)):
                raise RuntimeError("Could not unregister controlled SQLite clock")
            self.registered = False
