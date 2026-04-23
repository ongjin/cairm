public func new_engine() -> Engine {
    Engine(ptr: __swift_bridge__$new_engine())
}
public func searchStart<GenericIntoRustString: IntoRustString>(_ root_path: GenericIntoRustString, _ query: GenericIntoRustString, _ subtree: Bool, _ show_hidden: Bool) -> UInt64 {
    __swift_bridge__$search_start({ let rustString = root_path.intoRustString(); rustString.isOwned = false; return rustString.ptr }(), { let rustString = query.intoRustString(); rustString.isOwned = false; return rustString.ptr }(), subtree, show_hidden)
}
public func searchNextBatch(_ handle: UInt64) -> SearchBatch {
    SearchBatch(ptr: __swift_bridge__$search_next_batch(handle))
}
public func searchCancel(_ handle: UInt64) {
    __swift_bridge__$search_cancel(handle)
}
public enum FileKind {
    case Directory
    case Regular
    case Symlink
}
extension FileKind {
    func intoFfiRepr() -> __swift_bridge__$FileKind {
        switch self {
            case FileKind.Directory:
                return __swift_bridge__$FileKind(tag: __swift_bridge__$FileKind$Directory)
            case FileKind.Regular:
                return __swift_bridge__$FileKind(tag: __swift_bridge__$FileKind$Regular)
            case FileKind.Symlink:
                return __swift_bridge__$FileKind(tag: __swift_bridge__$FileKind$Symlink)
        }
    }
}
extension __swift_bridge__$FileKind {
    func intoSwiftRepr() -> FileKind {
        switch self.tag {
            case __swift_bridge__$FileKind$Directory:
                return FileKind.Directory
            case __swift_bridge__$FileKind$Regular:
                return FileKind.Regular
            case __swift_bridge__$FileKind$Symlink:
                return FileKind.Symlink
            default:
                fatalError("Unreachable")
        }
    }
}
extension __swift_bridge__$Option$FileKind {
    @inline(__always)
    func intoSwiftRepr() -> Optional<FileKind> {
        if self.is_some {
            return self.val.intoSwiftRepr()
        } else {
            return nil
        }
    }
    @inline(__always)
    static func fromSwiftRepr(_ val: Optional<FileKind>) -> __swift_bridge__$Option$FileKind {
        if let v = val {
            return __swift_bridge__$Option$FileKind(is_some: true, val: v.intoFfiRepr())
        } else {
            return __swift_bridge__$Option$FileKind(is_some: false, val: __swift_bridge__$FileKind())
        }
    }
}
extension FileKind: Vectorizable {
    public static func vecOfSelfNew() -> UnsafeMutableRawPointer {
        __swift_bridge__$Vec_FileKind$new()
    }

    public static func vecOfSelfFree(vecPtr: UnsafeMutableRawPointer) {
        __swift_bridge__$Vec_FileKind$drop(vecPtr)
    }

    public static func vecOfSelfPush(vecPtr: UnsafeMutableRawPointer, value: Self) {
        __swift_bridge__$Vec_FileKind$push(vecPtr, value.intoFfiRepr())
    }

    public static func vecOfSelfPop(vecPtr: UnsafeMutableRawPointer) -> Optional<Self> {
        let maybeEnum = __swift_bridge__$Vec_FileKind$pop(vecPtr)
        return maybeEnum.intoSwiftRepr()
    }

    public static func vecOfSelfGet(vecPtr: UnsafeMutableRawPointer, index: UInt) -> Optional<Self> {
        let maybeEnum = __swift_bridge__$Vec_FileKind$get(vecPtr, index)
        return maybeEnum.intoSwiftRepr()
    }

    public static func vecOfSelfGetMut(vecPtr: UnsafeMutableRawPointer, index: UInt) -> Optional<Self> {
        let maybeEnum = __swift_bridge__$Vec_FileKind$get_mut(vecPtr, index)
        return maybeEnum.intoSwiftRepr()
    }

    public static func vecOfSelfAsPtr(vecPtr: UnsafeMutableRawPointer) -> UnsafePointer<Self> {
        UnsafePointer<Self>(OpaquePointer(__swift_bridge__$Vec_FileKind$as_ptr(vecPtr)))
    }

    public static func vecOfSelfLen(vecPtr: UnsafeMutableRawPointer) -> UInt {
        __swift_bridge__$Vec_FileKind$len(vecPtr)
    }
}
public enum IconKind {
    case Folder
    case GenericFile
    case ExtensionHint(RustString)
}
extension IconKind {
    func intoFfiRepr() -> __swift_bridge__$IconKind {
        switch self {
            case IconKind.Folder:
                return {var val = __swift_bridge__$IconKind(); val.tag = __swift_bridge__$IconKind$Folder; return val }()
            case IconKind.GenericFile:
                return {var val = __swift_bridge__$IconKind(); val.tag = __swift_bridge__$IconKind$GenericFile; return val }()
            case IconKind.ExtensionHint(let _0):
                return __swift_bridge__$IconKind(tag: __swift_bridge__$IconKind$ExtensionHint, payload: __swift_bridge__$IconKindFields(ExtensionHint: __swift_bridge__$IconKind$FieldOfExtensionHint(_0: { let rustString = _0.intoRustString(); rustString.isOwned = false; return rustString.ptr }())))
        }
    }
}
extension __swift_bridge__$IconKind {
    func intoSwiftRepr() -> IconKind {
        switch self.tag {
            case __swift_bridge__$IconKind$Folder:
                return IconKind.Folder
            case __swift_bridge__$IconKind$GenericFile:
                return IconKind.GenericFile
            case __swift_bridge__$IconKind$ExtensionHint:
                return IconKind.ExtensionHint(RustString(ptr: self.payload.ExtensionHint._0))
            default:
                fatalError("Unreachable")
        }
    }
}
extension __swift_bridge__$Option$IconKind {
    @inline(__always)
    func intoSwiftRepr() -> Optional<IconKind> {
        if self.is_some {
            return self.val.intoSwiftRepr()
        } else {
            return nil
        }
    }
    @inline(__always)
    static func fromSwiftRepr(_ val: Optional<IconKind>) -> __swift_bridge__$Option$IconKind {
        if let v = val {
            return __swift_bridge__$Option$IconKind(is_some: true, val: v.intoFfiRepr())
        } else {
            return __swift_bridge__$Option$IconKind(is_some: false, val: __swift_bridge__$IconKind())
        }
    }
}
public struct FileEntry {
    public var path: RustString
    public var name: RustString
    public var size: UInt64
    public var modified_unix: Int64
    public var kind: FileKind
    public var is_hidden: Bool
    public var icon_kind: IconKind

    public init(path: RustString,name: RustString,size: UInt64,modified_unix: Int64,kind: FileKind,is_hidden: Bool,icon_kind: IconKind) {
        self.path = path
        self.name = name
        self.size = size
        self.modified_unix = modified_unix
        self.kind = kind
        self.is_hidden = is_hidden
        self.icon_kind = icon_kind
    }

    @inline(__always)
    func intoFfiRepr() -> __swift_bridge__$FileEntry {
        { let val = self; return __swift_bridge__$FileEntry(path: { let rustString = val.path.intoRustString(); rustString.isOwned = false; return rustString.ptr }(), name: { let rustString = val.name.intoRustString(); rustString.isOwned = false; return rustString.ptr }(), size: val.size, modified_unix: val.modified_unix, kind: val.kind.intoFfiRepr(), is_hidden: val.is_hidden, icon_kind: val.icon_kind.intoFfiRepr()); }()
    }
}
extension __swift_bridge__$FileEntry {
    @inline(__always)
    func intoSwiftRepr() -> FileEntry {
        { let val = self; return FileEntry(path: RustString(ptr: val.path), name: RustString(ptr: val.name), size: val.size, modified_unix: val.modified_unix, kind: val.kind.intoSwiftRepr(), is_hidden: val.is_hidden, icon_kind: val.icon_kind.intoSwiftRepr()); }()
    }
}
extension __swift_bridge__$Option$FileEntry {
    @inline(__always)
    func intoSwiftRepr() -> Optional<FileEntry> {
        if self.is_some {
            return self.val.intoSwiftRepr()
        } else {
            return nil
        }
    }

    @inline(__always)
    static func fromSwiftRepr(_ val: Optional<FileEntry>) -> __swift_bridge__$Option$FileEntry {
        if let v = val {
            return __swift_bridge__$Option$FileEntry(is_some: true, val: v.intoFfiRepr())
        } else {
            return __swift_bridge__$Option$FileEntry(is_some: false, val: __swift_bridge__$FileEntry())
        }
    }
}
public enum WalkerError {
    case PermissionDenied
    case NotFound
    case NotDirectory
    case Io(RustString)
}
extension WalkerError {
    func intoFfiRepr() -> __swift_bridge__$WalkerError {
        switch self {
            case WalkerError.PermissionDenied:
                return {var val = __swift_bridge__$WalkerError(); val.tag = __swift_bridge__$WalkerError$PermissionDenied; return val }()
            case WalkerError.NotFound:
                return {var val = __swift_bridge__$WalkerError(); val.tag = __swift_bridge__$WalkerError$NotFound; return val }()
            case WalkerError.NotDirectory:
                return {var val = __swift_bridge__$WalkerError(); val.tag = __swift_bridge__$WalkerError$NotDirectory; return val }()
            case WalkerError.Io(let _0):
                return __swift_bridge__$WalkerError(tag: __swift_bridge__$WalkerError$Io, payload: __swift_bridge__$WalkerErrorFields(Io: __swift_bridge__$WalkerError$FieldOfIo(_0: { let rustString = _0.intoRustString(); rustString.isOwned = false; return rustString.ptr }())))
        }
    }
}
extension __swift_bridge__$WalkerError {
    func intoSwiftRepr() -> WalkerError {
        switch self.tag {
            case __swift_bridge__$WalkerError$PermissionDenied:
                return WalkerError.PermissionDenied
            case __swift_bridge__$WalkerError$NotFound:
                return WalkerError.NotFound
            case __swift_bridge__$WalkerError$NotDirectory:
                return WalkerError.NotDirectory
            case __swift_bridge__$WalkerError$Io:
                return WalkerError.Io(RustString(ptr: self.payload.Io._0))
            default:
                fatalError("Unreachable")
        }
    }
}
extension __swift_bridge__$Option$WalkerError {
    @inline(__always)
    func intoSwiftRepr() -> Optional<WalkerError> {
        if self.is_some {
            return self.val.intoSwiftRepr()
        } else {
            return nil
        }
    }
    @inline(__always)
    static func fromSwiftRepr(_ val: Optional<WalkerError>) -> __swift_bridge__$Option$WalkerError {
        if let v = val {
            return __swift_bridge__$Option$WalkerError(is_some: true, val: v.intoFfiRepr())
        } else {
            return __swift_bridge__$Option$WalkerError(is_some: false, val: __swift_bridge__$WalkerError())
        }
    }
}
public enum PreviewError {
    case Binary
    case NotFound
    case PermissionDenied
    case Io(RustString)
}
extension PreviewError {
    func intoFfiRepr() -> __swift_bridge__$PreviewError {
        switch self {
            case PreviewError.Binary:
                return {var val = __swift_bridge__$PreviewError(); val.tag = __swift_bridge__$PreviewError$Binary; return val }()
            case PreviewError.NotFound:
                return {var val = __swift_bridge__$PreviewError(); val.tag = __swift_bridge__$PreviewError$NotFound; return val }()
            case PreviewError.PermissionDenied:
                return {var val = __swift_bridge__$PreviewError(); val.tag = __swift_bridge__$PreviewError$PermissionDenied; return val }()
            case PreviewError.Io(let _0):
                return __swift_bridge__$PreviewError(tag: __swift_bridge__$PreviewError$Io, payload: __swift_bridge__$PreviewErrorFields(Io: __swift_bridge__$PreviewError$FieldOfIo(_0: { let rustString = _0.intoRustString(); rustString.isOwned = false; return rustString.ptr }())))
        }
    }
}
extension __swift_bridge__$PreviewError {
    func intoSwiftRepr() -> PreviewError {
        switch self.tag {
            case __swift_bridge__$PreviewError$Binary:
                return PreviewError.Binary
            case __swift_bridge__$PreviewError$NotFound:
                return PreviewError.NotFound
            case __swift_bridge__$PreviewError$PermissionDenied:
                return PreviewError.PermissionDenied
            case __swift_bridge__$PreviewError$Io:
                return PreviewError.Io(RustString(ptr: self.payload.Io._0))
            default:
                fatalError("Unreachable")
        }
    }
}
extension __swift_bridge__$Option$PreviewError {
    @inline(__always)
    func intoSwiftRepr() -> Optional<PreviewError> {
        if self.is_some {
            return self.val.intoSwiftRepr()
        } else {
            return nil
        }
    }
    @inline(__always)
    static func fromSwiftRepr(_ val: Optional<PreviewError>) -> __swift_bridge__$Option$PreviewError {
        if let v = val {
            return __swift_bridge__$Option$PreviewError(is_some: true, val: v.intoFfiRepr())
        } else {
            return __swift_bridge__$Option$PreviewError(is_some: false, val: __swift_bridge__$PreviewError())
        }
    }
}

public class Engine: EngineRefMut {
    var isOwned: Bool = true

    public override init(ptr: UnsafeMutableRawPointer) {
        super.init(ptr: ptr)
    }

    deinit {
        if isOwned {
            __swift_bridge__$Engine$_free(ptr)
        }
    }
}
public class EngineRefMut: EngineRef {
    public override init(ptr: UnsafeMutableRawPointer) {
        super.init(ptr: ptr)
    }
}
extension EngineRefMut {
    public func set_show_hidden(_ show: Bool) {
        __swift_bridge__$Engine$set_show_hidden(ptr, show)
    }
}
public class EngineRef {
    var ptr: UnsafeMutableRawPointer

    public init(ptr: UnsafeMutableRawPointer) {
        self.ptr = ptr
    }
}
extension EngineRef {
    public func list_directory<GenericIntoRustString: IntoRustString>(_ path: GenericIntoRustString) throws -> FileListing {
        try { let val = __swift_bridge__$Engine$list_directory(ptr, { let rustString = path.intoRustString(); rustString.isOwned = false; return rustString.ptr }()); switch val.tag { case __swift_bridge__$ResultFileListingAndWalkerError$ResultOk: return FileListing(ptr: val.payload.ok) case __swift_bridge__$ResultFileListingAndWalkerError$ResultErr: throw val.payload.err.intoSwiftRepr() default: fatalError() } }()
    }

    public func preview_text<GenericIntoRustString: IntoRustString>(_ path: GenericIntoRustString) throws -> RustString {
        try { let val = __swift_bridge__$Engine$preview_text(ptr, { let rustString = path.intoRustString(); rustString.isOwned = false; return rustString.ptr }()); switch val.tag { case __swift_bridge__$ResultStringAndPreviewError$ResultOk: return RustString(ptr: val.payload.ok) case __swift_bridge__$ResultStringAndPreviewError$ResultErr: throw val.payload.err.intoSwiftRepr() default: fatalError() } }()
    }
}
extension Engine: Vectorizable {
    public static func vecOfSelfNew() -> UnsafeMutableRawPointer {
        __swift_bridge__$Vec_Engine$new()
    }

    public static func vecOfSelfFree(vecPtr: UnsafeMutableRawPointer) {
        __swift_bridge__$Vec_Engine$drop(vecPtr)
    }

    public static func vecOfSelfPush(vecPtr: UnsafeMutableRawPointer, value: Engine) {
        __swift_bridge__$Vec_Engine$push(vecPtr, {value.isOwned = false; return value.ptr;}())
    }

    public static func vecOfSelfPop(vecPtr: UnsafeMutableRawPointer) -> Optional<Self> {
        let pointer = __swift_bridge__$Vec_Engine$pop(vecPtr)
        if pointer == nil {
            return nil
        } else {
            return (Engine(ptr: pointer!) as! Self)
        }
    }

    public static func vecOfSelfGet(vecPtr: UnsafeMutableRawPointer, index: UInt) -> Optional<EngineRef> {
        let pointer = __swift_bridge__$Vec_Engine$get(vecPtr, index)
        if pointer == nil {
            return nil
        } else {
            return EngineRef(ptr: pointer!)
        }
    }

    public static func vecOfSelfGetMut(vecPtr: UnsafeMutableRawPointer, index: UInt) -> Optional<EngineRefMut> {
        let pointer = __swift_bridge__$Vec_Engine$get_mut(vecPtr, index)
        if pointer == nil {
            return nil
        } else {
            return EngineRefMut(ptr: pointer!)
        }
    }

    public static func vecOfSelfAsPtr(vecPtr: UnsafeMutableRawPointer) -> UnsafePointer<EngineRef> {
        UnsafePointer<EngineRef>(OpaquePointer(__swift_bridge__$Vec_Engine$as_ptr(vecPtr)))
    }

    public static func vecOfSelfLen(vecPtr: UnsafeMutableRawPointer) -> UInt {
        __swift_bridge__$Vec_Engine$len(vecPtr)
    }
}


public class FileListing: FileListingRefMut {
    var isOwned: Bool = true

    public override init(ptr: UnsafeMutableRawPointer) {
        super.init(ptr: ptr)
    }

    deinit {
        if isOwned {
            __swift_bridge__$FileListing$_free(ptr)
        }
    }
}
public class FileListingRefMut: FileListingRef {
    public override init(ptr: UnsafeMutableRawPointer) {
        super.init(ptr: ptr)
    }
}
public class FileListingRef {
    var ptr: UnsafeMutableRawPointer

    public init(ptr: UnsafeMutableRawPointer) {
        self.ptr = ptr
    }
}
extension FileListingRef {
    public func len() -> UInt {
        __swift_bridge__$FileListing$len(ptr)
    }

    public func entry(_ index: UInt) -> FileEntry {
        __swift_bridge__$FileListing$entry(ptr, index).intoSwiftRepr()
    }
}
extension FileListing: Vectorizable {
    public static func vecOfSelfNew() -> UnsafeMutableRawPointer {
        __swift_bridge__$Vec_FileListing$new()
    }

    public static func vecOfSelfFree(vecPtr: UnsafeMutableRawPointer) {
        __swift_bridge__$Vec_FileListing$drop(vecPtr)
    }

    public static func vecOfSelfPush(vecPtr: UnsafeMutableRawPointer, value: FileListing) {
        __swift_bridge__$Vec_FileListing$push(vecPtr, {value.isOwned = false; return value.ptr;}())
    }

    public static func vecOfSelfPop(vecPtr: UnsafeMutableRawPointer) -> Optional<Self> {
        let pointer = __swift_bridge__$Vec_FileListing$pop(vecPtr)
        if pointer == nil {
            return nil
        } else {
            return (FileListing(ptr: pointer!) as! Self)
        }
    }

    public static func vecOfSelfGet(vecPtr: UnsafeMutableRawPointer, index: UInt) -> Optional<FileListingRef> {
        let pointer = __swift_bridge__$Vec_FileListing$get(vecPtr, index)
        if pointer == nil {
            return nil
        } else {
            return FileListingRef(ptr: pointer!)
        }
    }

    public static func vecOfSelfGetMut(vecPtr: UnsafeMutableRawPointer, index: UInt) -> Optional<FileListingRefMut> {
        let pointer = __swift_bridge__$Vec_FileListing$get_mut(vecPtr, index)
        if pointer == nil {
            return nil
        } else {
            return FileListingRefMut(ptr: pointer!)
        }
    }

    public static func vecOfSelfAsPtr(vecPtr: UnsafeMutableRawPointer) -> UnsafePointer<FileListingRef> {
        UnsafePointer<FileListingRef>(OpaquePointer(__swift_bridge__$Vec_FileListing$as_ptr(vecPtr)))
    }

    public static func vecOfSelfLen(vecPtr: UnsafeMutableRawPointer) -> UInt {
        __swift_bridge__$Vec_FileListing$len(vecPtr)
    }
}


public class SearchBatch: SearchBatchRefMut {
    var isOwned: Bool = true

    public override init(ptr: UnsafeMutableRawPointer) {
        super.init(ptr: ptr)
    }

    deinit {
        if isOwned {
            __swift_bridge__$SearchBatch$_free(ptr)
        }
    }
}
public class SearchBatchRefMut: SearchBatchRef {
    public override init(ptr: UnsafeMutableRawPointer) {
        super.init(ptr: ptr)
    }
}
public class SearchBatchRef {
    var ptr: UnsafeMutableRawPointer

    public init(ptr: UnsafeMutableRawPointer) {
        self.ptr = ptr
    }
}
extension SearchBatchRef {
    public func isEnd() -> Bool {
        __swift_bridge__$SearchBatch$is_end(ptr)
    }

    public func len() -> UInt {
        __swift_bridge__$SearchBatch$len(ptr)
    }

    public func entry(_ index: UInt) -> FileEntry {
        __swift_bridge__$SearchBatch$entry(ptr, index).intoSwiftRepr()
    }
}
extension SearchBatch: Vectorizable {
    public static func vecOfSelfNew() -> UnsafeMutableRawPointer {
        __swift_bridge__$Vec_SearchBatch$new()
    }

    public static func vecOfSelfFree(vecPtr: UnsafeMutableRawPointer) {
        __swift_bridge__$Vec_SearchBatch$drop(vecPtr)
    }

    public static func vecOfSelfPush(vecPtr: UnsafeMutableRawPointer, value: SearchBatch) {
        __swift_bridge__$Vec_SearchBatch$push(vecPtr, {value.isOwned = false; return value.ptr;}())
    }

    public static func vecOfSelfPop(vecPtr: UnsafeMutableRawPointer) -> Optional<Self> {
        let pointer = __swift_bridge__$Vec_SearchBatch$pop(vecPtr)
        if pointer == nil {
            return nil
        } else {
            return (SearchBatch(ptr: pointer!) as! Self)
        }
    }

    public static func vecOfSelfGet(vecPtr: UnsafeMutableRawPointer, index: UInt) -> Optional<SearchBatchRef> {
        let pointer = __swift_bridge__$Vec_SearchBatch$get(vecPtr, index)
        if pointer == nil {
            return nil
        } else {
            return SearchBatchRef(ptr: pointer!)
        }
    }

    public static func vecOfSelfGetMut(vecPtr: UnsafeMutableRawPointer, index: UInt) -> Optional<SearchBatchRefMut> {
        let pointer = __swift_bridge__$Vec_SearchBatch$get_mut(vecPtr, index)
        if pointer == nil {
            return nil
        } else {
            return SearchBatchRefMut(ptr: pointer!)
        }
    }

    public static func vecOfSelfAsPtr(vecPtr: UnsafeMutableRawPointer) -> UnsafePointer<SearchBatchRef> {
        UnsafePointer<SearchBatchRef>(OpaquePointer(__swift_bridge__$Vec_SearchBatch$as_ptr(vecPtr)))
    }

    public static func vecOfSelfLen(vecPtr: UnsafeMutableRawPointer) -> UInt {
        __swift_bridge__$Vec_SearchBatch$len(vecPtr)
    }
}



public func ffi_index_open<GenericIntoRustString: IntoRustString>(_ root: GenericIntoRustString) -> UInt64 {
    __swift_bridge__$ffi_index_open({ let rustString = root.intoRustString(); rustString.isOwned = false; return rustString.ptr }())
}
public func ffi_index_close(_ handle: UInt64) {
    __swift_bridge__$ffi_index_close(handle)
}
public func ffi_index_query_fuzzy<GenericIntoRustString: IntoRustString>(_ handle: UInt64, _ query: GenericIntoRustString, _ limit: UInt32) -> FileHitList {
    FileHitList(ptr: __swift_bridge__$ffi_index_query_fuzzy(handle, { let rustString = query.intoRustString(); rustString.isOwned = false; return rustString.ptr }(), limit))
}
public func ffi_index_query_symbols<GenericIntoRustString: IntoRustString>(_ handle: UInt64, _ query: GenericIntoRustString, _ limit: UInt32) -> SymbolHitList {
    SymbolHitList(ptr: __swift_bridge__$ffi_index_query_symbols(handle, { let rustString = query.intoRustString(); rustString.isOwned = false; return rustString.ptr }(), limit))
}
public func ffi_index_query_git_dirty(_ handle: UInt64) -> FileHitList {
    FileHitList(ptr: __swift_bridge__$ffi_index_query_git_dirty(handle))
}
public struct FfiFileHit {
    public var path_rel: RustString
    public var score: UInt32
    public var kind_raw: UInt8

    public init(path_rel: RustString,score: UInt32,kind_raw: UInt8) {
        self.path_rel = path_rel
        self.score = score
        self.kind_raw = kind_raw
    }

    @inline(__always)
    func intoFfiRepr() -> __swift_bridge__$FfiFileHit {
        { let val = self; return __swift_bridge__$FfiFileHit(path_rel: { let rustString = val.path_rel.intoRustString(); rustString.isOwned = false; return rustString.ptr }(), score: val.score, kind_raw: val.kind_raw); }()
    }
}
extension __swift_bridge__$FfiFileHit {
    @inline(__always)
    func intoSwiftRepr() -> FfiFileHit {
        { let val = self; return FfiFileHit(path_rel: RustString(ptr: val.path_rel), score: val.score, kind_raw: val.kind_raw); }()
    }
}
extension __swift_bridge__$Option$FfiFileHit {
    @inline(__always)
    func intoSwiftRepr() -> Optional<FfiFileHit> {
        if self.is_some {
            return self.val.intoSwiftRepr()
        } else {
            return nil
        }
    }

    @inline(__always)
    static func fromSwiftRepr(_ val: Optional<FfiFileHit>) -> __swift_bridge__$Option$FfiFileHit {
        if let v = val {
            return __swift_bridge__$Option$FfiFileHit(is_some: true, val: v.intoFfiRepr())
        } else {
            return __swift_bridge__$Option$FfiFileHit(is_some: false, val: __swift_bridge__$FfiFileHit())
        }
    }
}
public struct FfiSymbolHit {
    public var path_rel: RustString
    public var name: RustString
    public var kind_raw: UInt8
    public var line: UInt32

    public init(path_rel: RustString,name: RustString,kind_raw: UInt8,line: UInt32) {
        self.path_rel = path_rel
        self.name = name
        self.kind_raw = kind_raw
        self.line = line
    }

    @inline(__always)
    func intoFfiRepr() -> __swift_bridge__$FfiSymbolHit {
        { let val = self; return __swift_bridge__$FfiSymbolHit(path_rel: { let rustString = val.path_rel.intoRustString(); rustString.isOwned = false; return rustString.ptr }(), name: { let rustString = val.name.intoRustString(); rustString.isOwned = false; return rustString.ptr }(), kind_raw: val.kind_raw, line: val.line); }()
    }
}
extension __swift_bridge__$FfiSymbolHit {
    @inline(__always)
    func intoSwiftRepr() -> FfiSymbolHit {
        { let val = self; return FfiSymbolHit(path_rel: RustString(ptr: val.path_rel), name: RustString(ptr: val.name), kind_raw: val.kind_raw, line: val.line); }()
    }
}
extension __swift_bridge__$Option$FfiSymbolHit {
    @inline(__always)
    func intoSwiftRepr() -> Optional<FfiSymbolHit> {
        if self.is_some {
            return self.val.intoSwiftRepr()
        } else {
            return nil
        }
    }

    @inline(__always)
    static func fromSwiftRepr(_ val: Optional<FfiSymbolHit>) -> __swift_bridge__$Option$FfiSymbolHit {
        if let v = val {
            return __swift_bridge__$Option$FfiSymbolHit(is_some: true, val: v.intoFfiRepr())
        } else {
            return __swift_bridge__$Option$FfiSymbolHit(is_some: false, val: __swift_bridge__$FfiSymbolHit())
        }
    }
}

public class FileHitList: FileHitListRefMut {
    var isOwned: Bool = true

    public override init(ptr: UnsafeMutableRawPointer) {
        super.init(ptr: ptr)
    }

    deinit {
        if isOwned {
            __swift_bridge__$FileHitList$_free(ptr)
        }
    }
}
public class FileHitListRefMut: FileHitListRef {
    public override init(ptr: UnsafeMutableRawPointer) {
        super.init(ptr: ptr)
    }
}
public class FileHitListRef {
    var ptr: UnsafeMutableRawPointer

    public init(ptr: UnsafeMutableRawPointer) {
        self.ptr = ptr
    }
}
extension FileHitListRef {
    public func len() -> UInt {
        __swift_bridge__$FileHitList$len(ptr)
    }

    public func at(_ index: UInt) -> FfiFileHit {
        __swift_bridge__$FileHitList$at(ptr, index).intoSwiftRepr()
    }
}
extension FileHitList: Vectorizable {
    public static func vecOfSelfNew() -> UnsafeMutableRawPointer {
        __swift_bridge__$Vec_FileHitList$new()
    }

    public static func vecOfSelfFree(vecPtr: UnsafeMutableRawPointer) {
        __swift_bridge__$Vec_FileHitList$drop(vecPtr)
    }

    public static func vecOfSelfPush(vecPtr: UnsafeMutableRawPointer, value: FileHitList) {
        __swift_bridge__$Vec_FileHitList$push(vecPtr, {value.isOwned = false; return value.ptr;}())
    }

    public static func vecOfSelfPop(vecPtr: UnsafeMutableRawPointer) -> Optional<Self> {
        let pointer = __swift_bridge__$Vec_FileHitList$pop(vecPtr)
        if pointer == nil {
            return nil
        } else {
            return (FileHitList(ptr: pointer!) as! Self)
        }
    }

    public static func vecOfSelfGet(vecPtr: UnsafeMutableRawPointer, index: UInt) -> Optional<FileHitListRef> {
        let pointer = __swift_bridge__$Vec_FileHitList$get(vecPtr, index)
        if pointer == nil {
            return nil
        } else {
            return FileHitListRef(ptr: pointer!)
        }
    }

    public static func vecOfSelfGetMut(vecPtr: UnsafeMutableRawPointer, index: UInt) -> Optional<FileHitListRefMut> {
        let pointer = __swift_bridge__$Vec_FileHitList$get_mut(vecPtr, index)
        if pointer == nil {
            return nil
        } else {
            return FileHitListRefMut(ptr: pointer!)
        }
    }

    public static func vecOfSelfAsPtr(vecPtr: UnsafeMutableRawPointer) -> UnsafePointer<FileHitListRef> {
        UnsafePointer<FileHitListRef>(OpaquePointer(__swift_bridge__$Vec_FileHitList$as_ptr(vecPtr)))
    }

    public static func vecOfSelfLen(vecPtr: UnsafeMutableRawPointer) -> UInt {
        __swift_bridge__$Vec_FileHitList$len(vecPtr)
    }
}


public class SymbolHitList: SymbolHitListRefMut {
    var isOwned: Bool = true

    public override init(ptr: UnsafeMutableRawPointer) {
        super.init(ptr: ptr)
    }

    deinit {
        if isOwned {
            __swift_bridge__$SymbolHitList$_free(ptr)
        }
    }
}
public class SymbolHitListRefMut: SymbolHitListRef {
    public override init(ptr: UnsafeMutableRawPointer) {
        super.init(ptr: ptr)
    }
}
public class SymbolHitListRef {
    var ptr: UnsafeMutableRawPointer

    public init(ptr: UnsafeMutableRawPointer) {
        self.ptr = ptr
    }
}
extension SymbolHitListRef {
    public func len() -> UInt {
        __swift_bridge__$SymbolHitList$len(ptr)
    }

    public func at(_ index: UInt) -> FfiSymbolHit {
        __swift_bridge__$SymbolHitList$at(ptr, index).intoSwiftRepr()
    }
}
extension SymbolHitList: Vectorizable {
    public static func vecOfSelfNew() -> UnsafeMutableRawPointer {
        __swift_bridge__$Vec_SymbolHitList$new()
    }

    public static func vecOfSelfFree(vecPtr: UnsafeMutableRawPointer) {
        __swift_bridge__$Vec_SymbolHitList$drop(vecPtr)
    }

    public static func vecOfSelfPush(vecPtr: UnsafeMutableRawPointer, value: SymbolHitList) {
        __swift_bridge__$Vec_SymbolHitList$push(vecPtr, {value.isOwned = false; return value.ptr;}())
    }

    public static func vecOfSelfPop(vecPtr: UnsafeMutableRawPointer) -> Optional<Self> {
        let pointer = __swift_bridge__$Vec_SymbolHitList$pop(vecPtr)
        if pointer == nil {
            return nil
        } else {
            return (SymbolHitList(ptr: pointer!) as! Self)
        }
    }

    public static func vecOfSelfGet(vecPtr: UnsafeMutableRawPointer, index: UInt) -> Optional<SymbolHitListRef> {
        let pointer = __swift_bridge__$Vec_SymbolHitList$get(vecPtr, index)
        if pointer == nil {
            return nil
        } else {
            return SymbolHitListRef(ptr: pointer!)
        }
    }

    public static func vecOfSelfGetMut(vecPtr: UnsafeMutableRawPointer, index: UInt) -> Optional<SymbolHitListRefMut> {
        let pointer = __swift_bridge__$Vec_SymbolHitList$get_mut(vecPtr, index)
        if pointer == nil {
            return nil
        } else {
            return SymbolHitListRefMut(ptr: pointer!)
        }
    }

    public static func vecOfSelfAsPtr(vecPtr: UnsafeMutableRawPointer) -> UnsafePointer<SymbolHitListRef> {
        UnsafePointer<SymbolHitListRef>(OpaquePointer(__swift_bridge__$Vec_SymbolHitList$as_ptr(vecPtr)))
    }

    public static func vecOfSelfLen(vecPtr: UnsafeMutableRawPointer) -> UInt {
        __swift_bridge__$Vec_SymbolHitList$len(vecPtr)
    }
}



public func ffi_content_start<GenericIntoRustString: IntoRustString>(_ handle: UInt64, _ pattern: GenericIntoRustString, _ is_regex: Bool) -> UInt64 {
    __swift_bridge__$ffi_content_start(handle, { let rustString = pattern.intoRustString(); rustString.isOwned = false; return rustString.ptr }(), is_regex)
}
public func ffi_content_poll(_ session: UInt64, _ max: UInt32) -> ContentHitList {
    ContentHitList(ptr: __swift_bridge__$ffi_content_poll(session, max))
}
public func ffi_content_cancel(_ session: UInt64) {
    __swift_bridge__$ffi_content_cancel(session)
}
public struct FfiContentHit {
    public var path_rel: RustString
    public var line: UInt32
    public var preview: RustString

    public init(path_rel: RustString,line: UInt32,preview: RustString) {
        self.path_rel = path_rel
        self.line = line
        self.preview = preview
    }

    @inline(__always)
    func intoFfiRepr() -> __swift_bridge__$FfiContentHit {
        { let val = self; return __swift_bridge__$FfiContentHit(path_rel: { let rustString = val.path_rel.intoRustString(); rustString.isOwned = false; return rustString.ptr }(), line: val.line, preview: { let rustString = val.preview.intoRustString(); rustString.isOwned = false; return rustString.ptr }()); }()
    }
}
extension __swift_bridge__$FfiContentHit {
    @inline(__always)
    func intoSwiftRepr() -> FfiContentHit {
        { let val = self; return FfiContentHit(path_rel: RustString(ptr: val.path_rel), line: val.line, preview: RustString(ptr: val.preview)); }()
    }
}
extension __swift_bridge__$Option$FfiContentHit {
    @inline(__always)
    func intoSwiftRepr() -> Optional<FfiContentHit> {
        if self.is_some {
            return self.val.intoSwiftRepr()
        } else {
            return nil
        }
    }

    @inline(__always)
    static func fromSwiftRepr(_ val: Optional<FfiContentHit>) -> __swift_bridge__$Option$FfiContentHit {
        if let v = val {
            return __swift_bridge__$Option$FfiContentHit(is_some: true, val: v.intoFfiRepr())
        } else {
            return __swift_bridge__$Option$FfiContentHit(is_some: false, val: __swift_bridge__$FfiContentHit())
        }
    }
}

public class ContentHitList: ContentHitListRefMut {
    var isOwned: Bool = true

    public override init(ptr: UnsafeMutableRawPointer) {
        super.init(ptr: ptr)
    }

    deinit {
        if isOwned {
            __swift_bridge__$ContentHitList$_free(ptr)
        }
    }
}
public class ContentHitListRefMut: ContentHitListRef {
    public override init(ptr: UnsafeMutableRawPointer) {
        super.init(ptr: ptr)
    }
}
public class ContentHitListRef {
    var ptr: UnsafeMutableRawPointer

    public init(ptr: UnsafeMutableRawPointer) {
        self.ptr = ptr
    }
}
extension ContentHitListRef {
    public func len() -> UInt {
        __swift_bridge__$ContentHitList$len(ptr)
    }

    public func at(_ index: UInt) -> FfiContentHit {
        __swift_bridge__$ContentHitList$at(ptr, index).intoSwiftRepr()
    }
}
extension ContentHitList: Vectorizable {
    public static func vecOfSelfNew() -> UnsafeMutableRawPointer {
        __swift_bridge__$Vec_ContentHitList$new()
    }

    public static func vecOfSelfFree(vecPtr: UnsafeMutableRawPointer) {
        __swift_bridge__$Vec_ContentHitList$drop(vecPtr)
    }

    public static func vecOfSelfPush(vecPtr: UnsafeMutableRawPointer, value: ContentHitList) {
        __swift_bridge__$Vec_ContentHitList$push(vecPtr, {value.isOwned = false; return value.ptr;}())
    }

    public static func vecOfSelfPop(vecPtr: UnsafeMutableRawPointer) -> Optional<Self> {
        let pointer = __swift_bridge__$Vec_ContentHitList$pop(vecPtr)
        if pointer == nil {
            return nil
        } else {
            return (ContentHitList(ptr: pointer!) as! Self)
        }
    }

    public static func vecOfSelfGet(vecPtr: UnsafeMutableRawPointer, index: UInt) -> Optional<ContentHitListRef> {
        let pointer = __swift_bridge__$Vec_ContentHitList$get(vecPtr, index)
        if pointer == nil {
            return nil
        } else {
            return ContentHitListRef(ptr: pointer!)
        }
    }

    public static func vecOfSelfGetMut(vecPtr: UnsafeMutableRawPointer, index: UInt) -> Optional<ContentHitListRefMut> {
        let pointer = __swift_bridge__$Vec_ContentHitList$get_mut(vecPtr, index)
        if pointer == nil {
            return nil
        } else {
            return ContentHitListRefMut(ptr: pointer!)
        }
    }

    public static func vecOfSelfAsPtr(vecPtr: UnsafeMutableRawPointer) -> UnsafePointer<ContentHitListRef> {
        UnsafePointer<ContentHitListRef>(OpaquePointer(__swift_bridge__$Vec_ContentHitList$as_ptr(vecPtr)))
    }

    public static func vecOfSelfLen(vecPtr: UnsafeMutableRawPointer) -> UInt {
        __swift_bridge__$Vec_ContentHitList$len(vecPtr)
    }
}



public func ffi_git_snapshot<GenericIntoRustString: IntoRustString>(_ root: GenericIntoRustString) -> Optional<FfiGitSnapshot> {
    __swift_bridge__$ffi_git_snapshot({ let rustString = root.intoRustString(); rustString.isOwned = false; return rustString.ptr }()).intoSwiftRepr()
}
public func ffi_git_modified_paths<GenericIntoRustString: IntoRustString>(_ root: GenericIntoRustString) -> GitPathList {
    GitPathList(ptr: __swift_bridge__$ffi_git_modified_paths({ let rustString = root.intoRustString(); rustString.isOwned = false; return rustString.ptr }()))
}
public func ffi_git_added_paths<GenericIntoRustString: IntoRustString>(_ root: GenericIntoRustString) -> GitPathList {
    GitPathList(ptr: __swift_bridge__$ffi_git_added_paths({ let rustString = root.intoRustString(); rustString.isOwned = false; return rustString.ptr }()))
}
public func ffi_git_deleted_paths<GenericIntoRustString: IntoRustString>(_ root: GenericIntoRustString) -> GitPathList {
    GitPathList(ptr: __swift_bridge__$ffi_git_deleted_paths({ let rustString = root.intoRustString(); rustString.isOwned = false; return rustString.ptr }()))
}
public func ffi_git_untracked_paths<GenericIntoRustString: IntoRustString>(_ root: GenericIntoRustString) -> GitPathList {
    GitPathList(ptr: __swift_bridge__$ffi_git_untracked_paths({ let rustString = root.intoRustString(); rustString.isOwned = false; return rustString.ptr }()))
}
public func ffi_git_full_snapshot<GenericIntoRustString: IntoRustString>(_ root: GenericIntoRustString) -> Optional<GitFullSnapshot> {
    { let val = __swift_bridge__$ffi_git_full_snapshot({ let rustString = root.intoRustString(); rustString.isOwned = false; return rustString.ptr }()); if val != nil { return GitFullSnapshot(ptr: val!) } else { return nil } }()
}
public struct FfiGitSnapshot {
    public var branch: RustString
    public var modified_count: UInt32
    public var untracked_count: UInt32
    public var added_count: UInt32
    public var deleted_count: UInt32

    public init(branch: RustString,modified_count: UInt32,untracked_count: UInt32,added_count: UInt32,deleted_count: UInt32) {
        self.branch = branch
        self.modified_count = modified_count
        self.untracked_count = untracked_count
        self.added_count = added_count
        self.deleted_count = deleted_count
    }

    @inline(__always)
    func intoFfiRepr() -> __swift_bridge__$FfiGitSnapshot {
        { let val = self; return __swift_bridge__$FfiGitSnapshot(branch: { let rustString = val.branch.intoRustString(); rustString.isOwned = false; return rustString.ptr }(), modified_count: val.modified_count, untracked_count: val.untracked_count, added_count: val.added_count, deleted_count: val.deleted_count); }()
    }
}
extension __swift_bridge__$FfiGitSnapshot {
    @inline(__always)
    func intoSwiftRepr() -> FfiGitSnapshot {
        { let val = self; return FfiGitSnapshot(branch: RustString(ptr: val.branch), modified_count: val.modified_count, untracked_count: val.untracked_count, added_count: val.added_count, deleted_count: val.deleted_count); }()
    }
}
extension __swift_bridge__$Option$FfiGitSnapshot {
    @inline(__always)
    func intoSwiftRepr() -> Optional<FfiGitSnapshot> {
        if self.is_some {
            return self.val.intoSwiftRepr()
        } else {
            return nil
        }
    }

    @inline(__always)
    static func fromSwiftRepr(_ val: Optional<FfiGitSnapshot>) -> __swift_bridge__$Option$FfiGitSnapshot {
        if let v = val {
            return __swift_bridge__$Option$FfiGitSnapshot(is_some: true, val: v.intoFfiRepr())
        } else {
            return __swift_bridge__$Option$FfiGitSnapshot(is_some: false, val: __swift_bridge__$FfiGitSnapshot())
        }
    }
}

public class GitPathList: GitPathListRefMut {
    var isOwned: Bool = true

    public override init(ptr: UnsafeMutableRawPointer) {
        super.init(ptr: ptr)
    }

    deinit {
        if isOwned {
            __swift_bridge__$GitPathList$_free(ptr)
        }
    }
}
public class GitPathListRefMut: GitPathListRef {
    public override init(ptr: UnsafeMutableRawPointer) {
        super.init(ptr: ptr)
    }
}
public class GitPathListRef {
    var ptr: UnsafeMutableRawPointer

    public init(ptr: UnsafeMutableRawPointer) {
        self.ptr = ptr
    }
}
extension GitPathListRef {
    public func len() -> UInt {
        __swift_bridge__$GitPathList$len(ptr)
    }

    public func at(_ index: UInt) -> RustString {
        RustString(ptr: __swift_bridge__$GitPathList$at(ptr, index))
    }
}
extension GitPathList: Vectorizable {
    public static func vecOfSelfNew() -> UnsafeMutableRawPointer {
        __swift_bridge__$Vec_GitPathList$new()
    }

    public static func vecOfSelfFree(vecPtr: UnsafeMutableRawPointer) {
        __swift_bridge__$Vec_GitPathList$drop(vecPtr)
    }

    public static func vecOfSelfPush(vecPtr: UnsafeMutableRawPointer, value: GitPathList) {
        __swift_bridge__$Vec_GitPathList$push(vecPtr, {value.isOwned = false; return value.ptr;}())
    }

    public static func vecOfSelfPop(vecPtr: UnsafeMutableRawPointer) -> Optional<Self> {
        let pointer = __swift_bridge__$Vec_GitPathList$pop(vecPtr)
        if pointer == nil {
            return nil
        } else {
            return (GitPathList(ptr: pointer!) as! Self)
        }
    }

    public static func vecOfSelfGet(vecPtr: UnsafeMutableRawPointer, index: UInt) -> Optional<GitPathListRef> {
        let pointer = __swift_bridge__$Vec_GitPathList$get(vecPtr, index)
        if pointer == nil {
            return nil
        } else {
            return GitPathListRef(ptr: pointer!)
        }
    }

    public static func vecOfSelfGetMut(vecPtr: UnsafeMutableRawPointer, index: UInt) -> Optional<GitPathListRefMut> {
        let pointer = __swift_bridge__$Vec_GitPathList$get_mut(vecPtr, index)
        if pointer == nil {
            return nil
        } else {
            return GitPathListRefMut(ptr: pointer!)
        }
    }

    public static func vecOfSelfAsPtr(vecPtr: UnsafeMutableRawPointer) -> UnsafePointer<GitPathListRef> {
        UnsafePointer<GitPathListRef>(OpaquePointer(__swift_bridge__$Vec_GitPathList$as_ptr(vecPtr)))
    }

    public static func vecOfSelfLen(vecPtr: UnsafeMutableRawPointer) -> UInt {
        __swift_bridge__$Vec_GitPathList$len(vecPtr)
    }
}


public class GitFullSnapshot: GitFullSnapshotRefMut {
    var isOwned: Bool = true

    public override init(ptr: UnsafeMutableRawPointer) {
        super.init(ptr: ptr)
    }

    deinit {
        if isOwned {
            __swift_bridge__$GitFullSnapshot$_free(ptr)
        }
    }
}
public class GitFullSnapshotRefMut: GitFullSnapshotRef {
    public override init(ptr: UnsafeMutableRawPointer) {
        super.init(ptr: ptr)
    }
}
public class GitFullSnapshotRef {
    var ptr: UnsafeMutableRawPointer

    public init(ptr: UnsafeMutableRawPointer) {
        self.ptr = ptr
    }
}
extension GitFullSnapshotRef {
    public func branch() -> RustString {
        RustString(ptr: __swift_bridge__$GitFullSnapshot$branch(ptr))
    }

    public func modified_count() -> UInt32 {
        __swift_bridge__$GitFullSnapshot$modified_count(ptr)
    }

    public func added_count() -> UInt32 {
        __swift_bridge__$GitFullSnapshot$added_count(ptr)
    }

    public func deleted_count() -> UInt32 {
        __swift_bridge__$GitFullSnapshot$deleted_count(ptr)
    }

    public func untracked_count() -> UInt32 {
        __swift_bridge__$GitFullSnapshot$untracked_count(ptr)
    }

    public func modified_len() -> UInt {
        __swift_bridge__$GitFullSnapshot$modified_len(ptr)
    }

    public func modified_at(_ index: UInt) -> RustString {
        RustString(ptr: __swift_bridge__$GitFullSnapshot$modified_at(ptr, index))
    }

    public func added_len() -> UInt {
        __swift_bridge__$GitFullSnapshot$added_len(ptr)
    }

    public func added_at(_ index: UInt) -> RustString {
        RustString(ptr: __swift_bridge__$GitFullSnapshot$added_at(ptr, index))
    }

    public func deleted_len() -> UInt {
        __swift_bridge__$GitFullSnapshot$deleted_len(ptr)
    }

    public func deleted_at(_ index: UInt) -> RustString {
        RustString(ptr: __swift_bridge__$GitFullSnapshot$deleted_at(ptr, index))
    }

    public func untracked_len() -> UInt {
        __swift_bridge__$GitFullSnapshot$untracked_len(ptr)
    }

    public func untracked_at(_ index: UInt) -> RustString {
        RustString(ptr: __swift_bridge__$GitFullSnapshot$untracked_at(ptr, index))
    }
}
extension GitFullSnapshot: Vectorizable {
    public static func vecOfSelfNew() -> UnsafeMutableRawPointer {
        __swift_bridge__$Vec_GitFullSnapshot$new()
    }

    public static func vecOfSelfFree(vecPtr: UnsafeMutableRawPointer) {
        __swift_bridge__$Vec_GitFullSnapshot$drop(vecPtr)
    }

    public static func vecOfSelfPush(vecPtr: UnsafeMutableRawPointer, value: GitFullSnapshot) {
        __swift_bridge__$Vec_GitFullSnapshot$push(vecPtr, {value.isOwned = false; return value.ptr;}())
    }

    public static func vecOfSelfPop(vecPtr: UnsafeMutableRawPointer) -> Optional<Self> {
        let pointer = __swift_bridge__$Vec_GitFullSnapshot$pop(vecPtr)
        if pointer == nil {
            return nil
        } else {
            return (GitFullSnapshot(ptr: pointer!) as! Self)
        }
    }

    public static func vecOfSelfGet(vecPtr: UnsafeMutableRawPointer, index: UInt) -> Optional<GitFullSnapshotRef> {
        let pointer = __swift_bridge__$Vec_GitFullSnapshot$get(vecPtr, index)
        if pointer == nil {
            return nil
        } else {
            return GitFullSnapshotRef(ptr: pointer!)
        }
    }

    public static func vecOfSelfGetMut(vecPtr: UnsafeMutableRawPointer, index: UInt) -> Optional<GitFullSnapshotRefMut> {
        let pointer = __swift_bridge__$Vec_GitFullSnapshot$get_mut(vecPtr, index)
        if pointer == nil {
            return nil
        } else {
            return GitFullSnapshotRefMut(ptr: pointer!)
        }
    }

    public static func vecOfSelfAsPtr(vecPtr: UnsafeMutableRawPointer) -> UnsafePointer<GitFullSnapshotRef> {
        UnsafePointer<GitFullSnapshotRef>(OpaquePointer(__swift_bridge__$Vec_GitFullSnapshot$as_ptr(vecPtr)))
    }

    public static func vecOfSelfLen(vecPtr: UnsafeMutableRawPointer) -> UInt {
        __swift_bridge__$Vec_GitFullSnapshot$len(vecPtr)
    }
}



@_cdecl("__swift_bridge__$HostKeyCallback$ask_host_key")
func __swift_bridge__HostKeyCallback_ask_host_key (_ this: UnsafeMutableRawPointer, _ host: UnsafeMutableRawPointer, _ port: UInt16, _ offer: __swift_bridge__$HostKeyOffer, _ state: UnsafeMutableRawPointer) -> UnsafeMutableRawPointer {
    { let rustString = Unmanaged<HostKeyCallback>.fromOpaque(this).takeUnretainedValue().askHostKey(host: RustString(ptr: host), port: port, offer: offer.intoSwiftRepr(), state: RustString(ptr: state)).intoRustString(); rustString.isOwned = false; return rustString.ptr }()
}

@_cdecl("__swift_bridge__$PassphraseCallback$ask_passphrase")
func __swift_bridge__PassphraseCallback_ask_passphrase (_ this: UnsafeMutableRawPointer, _ key_path: UnsafeMutableRawPointer) -> UnsafeMutableRawPointer? {
    { if let rustString = optionalStringIntoRustString(Unmanaged<PassphraseCallback>.fromOpaque(this).takeUnretainedValue().askPassphrase(key_path: RustString(ptr: key_path))) { rustString.isOwned = false; return rustString.ptr } else { return nil } }()
}

@_cdecl("__swift_bridge__$PasswordCallback$ask_password")
func __swift_bridge__PasswordCallback_ask_password (_ this: UnsafeMutableRawPointer, _ host: UnsafeMutableRawPointer, _ user: UnsafeMutableRawPointer) -> UnsafeMutableRawPointer? {
    { if let rustString = optionalStringIntoRustString(Unmanaged<PasswordCallback>.fromOpaque(this).takeUnretainedValue().askPassword(host: RustString(ptr: host), user: RustString(ptr: user))) { rustString.isOwned = false; return rustString.ptr } else { return nil } }()
}

public func ssh_pool_new() -> SshPoolBridge {
    SshPoolBridge(ptr: __swift_bridge__$ssh_pool_new())
}
public func ssh_pool_list_configured_hosts() -> RustVec<RustString> {
    RustVec(ptr: __swift_bridge__$ssh_pool_list_configured_hosts())
}
public func ssh_pool_connect(_ pool: SshPoolBridgeRef, _ spec: ConnectSpecBridge, _ hostkey_cb: HostKeyCallback, _ passphrase_cb: PassphraseCallback, _ password_cb: PasswordCallback) throws -> ConnKeyBridge {
    try { let val = __swift_bridge__$ssh_pool_connect(pool.ptr, spec.intoFfiRepr(), Unmanaged.passRetained(hostkey_cb).toOpaque(), Unmanaged.passRetained(passphrase_cb).toOpaque(), Unmanaged.passRetained(password_cb).toOpaque()); switch val.tag { case __swift_bridge__$ResultConnKeyBridgeAndString$ResultOk: return val.payload.ok.intoSwiftRepr() case __swift_bridge__$ResultConnKeyBridgeAndString$ResultErr: throw RustString(ptr: val.payload.err) default: fatalError() } }()
}
public func ssh_pool_disconnect(_ pool: SshPoolBridgeRef, _ key: ConnKeyBridge) {
    __swift_bridge__$ssh_pool_disconnect(pool.ptr, key.intoFfiRepr())
}
public func ssh_pool_close_all(_ pool: SshPoolBridgeRef) {
    __swift_bridge__$ssh_pool_close_all(pool.ptr)
}
public func ssh_open_sftp(_ pool: SshPoolBridgeRef, _ key: ConnKeyBridge) throws -> SftpHandleBridge {
    try { let val = __swift_bridge__$ssh_open_sftp(pool.ptr, key.intoFfiRepr()); if val.is_ok { return SftpHandleBridge(ptr: val.ok_or_err!) } else { throw RustString(ptr: val.ok_or_err!) } }()
}
public func sftp_list<GenericIntoRustString: IntoRustString>(_ h: SftpHandleBridgeRef, _ path: GenericIntoRustString) throws -> SftpListingBridge {
    try { let val = __swift_bridge__$sftp_list(h.ptr, { let rustString = path.intoRustString(); rustString.isOwned = false; return rustString.ptr }()); if val.is_ok { return SftpListingBridge(ptr: val.ok_or_err!) } else { throw RustString(ptr: val.ok_or_err!) } }()
}
public func sftp_realpath<GenericIntoRustString: IntoRustString>(_ h: SftpHandleBridgeRef, _ path: GenericIntoRustString) throws -> RustString {
    try { let val = __swift_bridge__$sftp_realpath(h.ptr, { let rustString = path.intoRustString(); rustString.isOwned = false; return rustString.ptr }()); if val.is_ok { return RustString(ptr: val.ok_or_err!) } else { throw RustString(ptr: val.ok_or_err!) } }()
}
public func sftp_stat<GenericIntoRustString: IntoRustString>(_ h: SftpHandleBridgeRef, _ path: GenericIntoRustString) throws -> FileStatBridge {
    try { let val = __swift_bridge__$sftp_stat(h.ptr, { let rustString = path.intoRustString(); rustString.isOwned = false; return rustString.ptr }()); switch val.tag { case __swift_bridge__$ResultFileStatBridgeAndString$ResultOk: return val.payload.ok.intoSwiftRepr() case __swift_bridge__$ResultFileStatBridgeAndString$ResultErr: throw RustString(ptr: val.payload.err) default: fatalError() } }()
}
public func sftp_mkdir<GenericIntoRustString: IntoRustString>(_ h: SftpHandleBridgeRef, _ path: GenericIntoRustString) throws -> () {
    try { let val = __swift_bridge__$sftp_mkdir(h.ptr, { let rustString = path.intoRustString(); rustString.isOwned = false; return rustString.ptr }()); if val != nil { throw RustString(ptr: val!) } else { return } }()
}
public func sftp_rename<GenericIntoRustString: IntoRustString>(_ h: SftpHandleBridgeRef, _ from: GenericIntoRustString, _ to: GenericIntoRustString) throws -> () {
    try { let val = __swift_bridge__$sftp_rename(h.ptr, { let rustString = from.intoRustString(); rustString.isOwned = false; return rustString.ptr }(), { let rustString = to.intoRustString(); rustString.isOwned = false; return rustString.ptr }()); if val != nil { throw RustString(ptr: val!) } else { return } }()
}
public func sftp_unlink<GenericIntoRustString: IntoRustString>(_ h: SftpHandleBridgeRef, _ path: GenericIntoRustString) throws -> () {
    try { let val = __swift_bridge__$sftp_unlink(h.ptr, { let rustString = path.intoRustString(); rustString.isOwned = false; return rustString.ptr }()); if val != nil { throw RustString(ptr: val!) } else { return } }()
}
public func sftp_read_head<GenericIntoRustString: IntoRustString>(_ h: SftpHandleBridgeRef, _ path: GenericIntoRustString, _ max: UInt32) throws -> RustVec<UInt8> {
    try { let val = __swift_bridge__$sftp_read_head(h.ptr, { let rustString = path.intoRustString(); rustString.isOwned = false; return rustString.ptr }(), max); if val.is_ok { return RustVec(ptr: val.ok_or_err!) } else { throw RustString(ptr: val.ok_or_err!) } }()
}
public func cancel_flag_new() -> CancelFlagBridge {
    CancelFlagBridge(ptr: __swift_bridge__$cancel_flag_new())
}
public func cancel_flag_cancel(_ f: CancelFlagBridgeRef) {
    __swift_bridge__$cancel_flag_cancel(f.ptr)
}
public func sftp_download_sync<GenericIntoRustString: IntoRustString>(_ h: SftpHandleBridgeRef, _ remote: GenericIntoRustString, _ local: GenericIntoRustString, _ cancel: CancelFlagBridgeRef) throws -> () {
    try { let val = __swift_bridge__$sftp_download_sync(h.ptr, { let rustString = remote.intoRustString(); rustString.isOwned = false; return rustString.ptr }(), { let rustString = local.intoRustString(); rustString.isOwned = false; return rustString.ptr }(), cancel.ptr); if val != nil { throw RustString(ptr: val!) } else { return } }()
}
public func sftp_upload_sync<GenericIntoRustString: IntoRustString>(_ h: SftpHandleBridgeRef, _ local: GenericIntoRustString, _ remote: GenericIntoRustString, _ cancel: CancelFlagBridgeRef) throws -> () {
    try { let val = __swift_bridge__$sftp_upload_sync(h.ptr, { let rustString = local.intoRustString(); rustString.isOwned = false; return rustString.ptr }(), { let rustString = remote.intoRustString(); rustString.isOwned = false; return rustString.ptr }(), cancel.ptr); if val != nil { throw RustString(ptr: val!) } else { return } }()
}
public func sftp_progress_poll(_ h: SftpHandleBridgeRef) -> UInt64 {
    __swift_bridge__$sftp_progress_poll(h.ptr)
}
public func sftp_listing_len(_ listing: SftpListingBridgeRef) -> UInt {
    __swift_bridge__$sftp_listing_len(listing.ptr)
}
public func sftp_listing_entry(_ listing: SftpListingBridgeRef, _ index: UInt) -> FileEntryBridge {
    __swift_bridge__$sftp_listing_entry(listing.ptr, index).intoSwiftRepr()
}
public struct ConnKeyBridge {
    public var user: RustString
    public var hostname: RustString
    public var port: UInt16
    public var config_hash_hex: RustString

    public init(user: RustString,hostname: RustString,port: UInt16,config_hash_hex: RustString) {
        self.user = user
        self.hostname = hostname
        self.port = port
        self.config_hash_hex = config_hash_hex
    }

    @inline(__always)
    func intoFfiRepr() -> __swift_bridge__$ConnKeyBridge {
        { let val = self; return __swift_bridge__$ConnKeyBridge(user: { let rustString = val.user.intoRustString(); rustString.isOwned = false; return rustString.ptr }(), hostname: { let rustString = val.hostname.intoRustString(); rustString.isOwned = false; return rustString.ptr }(), port: val.port, config_hash_hex: { let rustString = val.config_hash_hex.intoRustString(); rustString.isOwned = false; return rustString.ptr }()); }()
    }
}
extension __swift_bridge__$ConnKeyBridge {
    @inline(__always)
    func intoSwiftRepr() -> ConnKeyBridge {
        { let val = self; return ConnKeyBridge(user: RustString(ptr: val.user), hostname: RustString(ptr: val.hostname), port: val.port, config_hash_hex: RustString(ptr: val.config_hash_hex)); }()
    }
}
extension __swift_bridge__$Option$ConnKeyBridge {
    @inline(__always)
    func intoSwiftRepr() -> Optional<ConnKeyBridge> {
        if self.is_some {
            return self.val.intoSwiftRepr()
        } else {
            return nil
        }
    }

    @inline(__always)
    static func fromSwiftRepr(_ val: Optional<ConnKeyBridge>) -> __swift_bridge__$Option$ConnKeyBridge {
        if let v = val {
            return __swift_bridge__$Option$ConnKeyBridge(is_some: true, val: v.intoFfiRepr())
        } else {
            return __swift_bridge__$Option$ConnKeyBridge(is_some: false, val: __swift_bridge__$ConnKeyBridge())
        }
    }
}
public struct FileEntryBridge {
    public var name: RustString
    public var is_dir: Bool
    public var size: UInt64
    public var mtime: Int64
    public var mode: UInt32

    public init(name: RustString,is_dir: Bool,size: UInt64,mtime: Int64,mode: UInt32) {
        self.name = name
        self.is_dir = is_dir
        self.size = size
        self.mtime = mtime
        self.mode = mode
    }

    @inline(__always)
    func intoFfiRepr() -> __swift_bridge__$FileEntryBridge {
        { let val = self; return __swift_bridge__$FileEntryBridge(name: { let rustString = val.name.intoRustString(); rustString.isOwned = false; return rustString.ptr }(), is_dir: val.is_dir, size: val.size, mtime: val.mtime, mode: val.mode); }()
    }
}
extension __swift_bridge__$FileEntryBridge {
    @inline(__always)
    func intoSwiftRepr() -> FileEntryBridge {
        { let val = self; return FileEntryBridge(name: RustString(ptr: val.name), is_dir: val.is_dir, size: val.size, mtime: val.mtime, mode: val.mode); }()
    }
}
extension __swift_bridge__$Option$FileEntryBridge {
    @inline(__always)
    func intoSwiftRepr() -> Optional<FileEntryBridge> {
        if self.is_some {
            return self.val.intoSwiftRepr()
        } else {
            return nil
        }
    }

    @inline(__always)
    static func fromSwiftRepr(_ val: Optional<FileEntryBridge>) -> __swift_bridge__$Option$FileEntryBridge {
        if let v = val {
            return __swift_bridge__$Option$FileEntryBridge(is_some: true, val: v.intoFfiRepr())
        } else {
            return __swift_bridge__$Option$FileEntryBridge(is_some: false, val: __swift_bridge__$FileEntryBridge())
        }
    }
}
public struct FileStatBridge {
    public var size: UInt64
    public var mtime: Int64
    public var mode: UInt32
    public var is_dir: Bool

    public init(size: UInt64,mtime: Int64,mode: UInt32,is_dir: Bool) {
        self.size = size
        self.mtime = mtime
        self.mode = mode
        self.is_dir = is_dir
    }

    @inline(__always)
    func intoFfiRepr() -> __swift_bridge__$FileStatBridge {
        { let val = self; return __swift_bridge__$FileStatBridge(size: val.size, mtime: val.mtime, mode: val.mode, is_dir: val.is_dir); }()
    }
}
extension __swift_bridge__$FileStatBridge {
    @inline(__always)
    func intoSwiftRepr() -> FileStatBridge {
        { let val = self; return FileStatBridge(size: val.size, mtime: val.mtime, mode: val.mode, is_dir: val.is_dir); }()
    }
}
extension __swift_bridge__$Option$FileStatBridge {
    @inline(__always)
    func intoSwiftRepr() -> Optional<FileStatBridge> {
        if self.is_some {
            return self.val.intoSwiftRepr()
        } else {
            return nil
        }
    }

    @inline(__always)
    static func fromSwiftRepr(_ val: Optional<FileStatBridge>) -> __swift_bridge__$Option$FileStatBridge {
        if let v = val {
            return __swift_bridge__$Option$FileStatBridge(is_some: true, val: v.intoFfiRepr())
        } else {
            return __swift_bridge__$Option$FileStatBridge(is_some: false, val: __swift_bridge__$FileStatBridge())
        }
    }
}
public struct ConnectSpecBridge {
    public var host_alias: RustString
    public var user_override: Optional<RustString>
    public var port_override: Optional<UInt16>
    public var identity_file_override: Optional<RustString>
    public var proxy_command_override: Optional<RustString>
    public var password_override: RustString

    public init(host_alias: RustString,user_override: Optional<RustString>,port_override: Optional<UInt16>,identity_file_override: Optional<RustString>,proxy_command_override: Optional<RustString>,password_override: RustString) {
        self.host_alias = host_alias
        self.user_override = user_override
        self.port_override = port_override
        self.identity_file_override = identity_file_override
        self.proxy_command_override = proxy_command_override
        self.password_override = password_override
    }

    @inline(__always)
    func intoFfiRepr() -> __swift_bridge__$ConnectSpecBridge {
        { let val = self; return __swift_bridge__$ConnectSpecBridge(host_alias: { let rustString = val.host_alias.intoRustString(); rustString.isOwned = false; return rustString.ptr }(), user_override: { if let rustString = optionalStringIntoRustString(val.user_override) { rustString.isOwned = false; return rustString.ptr } else { return nil } }(), port_override: val.port_override.intoFfiRepr(), identity_file_override: { if let rustString = optionalStringIntoRustString(val.identity_file_override) { rustString.isOwned = false; return rustString.ptr } else { return nil } }(), proxy_command_override: { if let rustString = optionalStringIntoRustString(val.proxy_command_override) { rustString.isOwned = false; return rustString.ptr } else { return nil } }(), password_override: { let rustString = val.password_override.intoRustString(); rustString.isOwned = false; return rustString.ptr }()); }()
    }
}
extension __swift_bridge__$ConnectSpecBridge {
    @inline(__always)
    func intoSwiftRepr() -> ConnectSpecBridge {
        { let val = self; return ConnectSpecBridge(host_alias: RustString(ptr: val.host_alias), user_override: { let val = val.user_override; if val != nil { return RustString(ptr: val!) } else { return nil } }(), port_override: val.port_override.intoSwiftRepr(), identity_file_override: { let val = val.identity_file_override; if val != nil { return RustString(ptr: val!) } else { return nil } }(), proxy_command_override: { let val = val.proxy_command_override; if val != nil { return RustString(ptr: val!) } else { return nil } }(), password_override: RustString(ptr: val.password_override)); }()
    }
}
extension __swift_bridge__$Option$ConnectSpecBridge {
    @inline(__always)
    func intoSwiftRepr() -> Optional<ConnectSpecBridge> {
        if self.is_some {
            return self.val.intoSwiftRepr()
        } else {
            return nil
        }
    }

    @inline(__always)
    static func fromSwiftRepr(_ val: Optional<ConnectSpecBridge>) -> __swift_bridge__$Option$ConnectSpecBridge {
        if let v = val {
            return __swift_bridge__$Option$ConnectSpecBridge(is_some: true, val: v.intoFfiRepr())
        } else {
            return __swift_bridge__$Option$ConnectSpecBridge(is_some: false, val: __swift_bridge__$ConnectSpecBridge())
        }
    }
}
public struct HostKeyOffer {
    public var algorithm: RustString
    public var blob_base64: RustString
    public var fingerprint: RustString

    public init(algorithm: RustString,blob_base64: RustString,fingerprint: RustString) {
        self.algorithm = algorithm
        self.blob_base64 = blob_base64
        self.fingerprint = fingerprint
    }

    @inline(__always)
    func intoFfiRepr() -> __swift_bridge__$HostKeyOffer {
        { let val = self; return __swift_bridge__$HostKeyOffer(algorithm: { let rustString = val.algorithm.intoRustString(); rustString.isOwned = false; return rustString.ptr }(), blob_base64: { let rustString = val.blob_base64.intoRustString(); rustString.isOwned = false; return rustString.ptr }(), fingerprint: { let rustString = val.fingerprint.intoRustString(); rustString.isOwned = false; return rustString.ptr }()); }()
    }
}
extension __swift_bridge__$HostKeyOffer {
    @inline(__always)
    func intoSwiftRepr() -> HostKeyOffer {
        { let val = self; return HostKeyOffer(algorithm: RustString(ptr: val.algorithm), blob_base64: RustString(ptr: val.blob_base64), fingerprint: RustString(ptr: val.fingerprint)); }()
    }
}
extension __swift_bridge__$Option$HostKeyOffer {
    @inline(__always)
    func intoSwiftRepr() -> Optional<HostKeyOffer> {
        if self.is_some {
            return self.val.intoSwiftRepr()
        } else {
            return nil
        }
    }

    @inline(__always)
    static func fromSwiftRepr(_ val: Optional<HostKeyOffer>) -> __swift_bridge__$Option$HostKeyOffer {
        if let v = val {
            return __swift_bridge__$Option$HostKeyOffer(is_some: true, val: v.intoFfiRepr())
        } else {
            return __swift_bridge__$Option$HostKeyOffer(is_some: false, val: __swift_bridge__$HostKeyOffer())
        }
    }
}

@_cdecl("__swift_bridge__$HostKeyCallback$_free")
func __swift_bridge__HostKeyCallback__free (ptr: UnsafeMutableRawPointer) {
    let _ = Unmanaged<HostKeyCallback>.fromOpaque(ptr).takeRetainedValue()
}


@_cdecl("__swift_bridge__$PassphraseCallback$_free")
func __swift_bridge__PassphraseCallback__free (ptr: UnsafeMutableRawPointer) {
    let _ = Unmanaged<PassphraseCallback>.fromOpaque(ptr).takeRetainedValue()
}


@_cdecl("__swift_bridge__$PasswordCallback$_free")
func __swift_bridge__PasswordCallback__free (ptr: UnsafeMutableRawPointer) {
    let _ = Unmanaged<PasswordCallback>.fromOpaque(ptr).takeRetainedValue()
}


public class SftpListingBridge: SftpListingBridgeRefMut {
    var isOwned: Bool = true

    public override init(ptr: UnsafeMutableRawPointer) {
        super.init(ptr: ptr)
    }

    deinit {
        if isOwned {
            __swift_bridge__$SftpListingBridge$_free(ptr)
        }
    }
}
public class SftpListingBridgeRefMut: SftpListingBridgeRef {
    public override init(ptr: UnsafeMutableRawPointer) {
        super.init(ptr: ptr)
    }
}
public class SftpListingBridgeRef {
    var ptr: UnsafeMutableRawPointer

    public init(ptr: UnsafeMutableRawPointer) {
        self.ptr = ptr
    }
}
extension SftpListingBridge: Vectorizable {
    public static func vecOfSelfNew() -> UnsafeMutableRawPointer {
        __swift_bridge__$Vec_SftpListingBridge$new()
    }

    public static func vecOfSelfFree(vecPtr: UnsafeMutableRawPointer) {
        __swift_bridge__$Vec_SftpListingBridge$drop(vecPtr)
    }

    public static func vecOfSelfPush(vecPtr: UnsafeMutableRawPointer, value: SftpListingBridge) {
        __swift_bridge__$Vec_SftpListingBridge$push(vecPtr, {value.isOwned = false; return value.ptr;}())
    }

    public static func vecOfSelfPop(vecPtr: UnsafeMutableRawPointer) -> Optional<Self> {
        let pointer = __swift_bridge__$Vec_SftpListingBridge$pop(vecPtr)
        if pointer == nil {
            return nil
        } else {
            return (SftpListingBridge(ptr: pointer!) as! Self)
        }
    }

    public static func vecOfSelfGet(vecPtr: UnsafeMutableRawPointer, index: UInt) -> Optional<SftpListingBridgeRef> {
        let pointer = __swift_bridge__$Vec_SftpListingBridge$get(vecPtr, index)
        if pointer == nil {
            return nil
        } else {
            return SftpListingBridgeRef(ptr: pointer!)
        }
    }

    public static func vecOfSelfGetMut(vecPtr: UnsafeMutableRawPointer, index: UInt) -> Optional<SftpListingBridgeRefMut> {
        let pointer = __swift_bridge__$Vec_SftpListingBridge$get_mut(vecPtr, index)
        if pointer == nil {
            return nil
        } else {
            return SftpListingBridgeRefMut(ptr: pointer!)
        }
    }

    public static func vecOfSelfAsPtr(vecPtr: UnsafeMutableRawPointer) -> UnsafePointer<SftpListingBridgeRef> {
        UnsafePointer<SftpListingBridgeRef>(OpaquePointer(__swift_bridge__$Vec_SftpListingBridge$as_ptr(vecPtr)))
    }

    public static func vecOfSelfLen(vecPtr: UnsafeMutableRawPointer) -> UInt {
        __swift_bridge__$Vec_SftpListingBridge$len(vecPtr)
    }
}


public class CancelFlagBridge: CancelFlagBridgeRefMut {
    var isOwned: Bool = true

    public override init(ptr: UnsafeMutableRawPointer) {
        super.init(ptr: ptr)
    }

    deinit {
        if isOwned {
            __swift_bridge__$CancelFlagBridge$_free(ptr)
        }
    }
}
public class CancelFlagBridgeRefMut: CancelFlagBridgeRef {
    public override init(ptr: UnsafeMutableRawPointer) {
        super.init(ptr: ptr)
    }
}
public class CancelFlagBridgeRef {
    var ptr: UnsafeMutableRawPointer

    public init(ptr: UnsafeMutableRawPointer) {
        self.ptr = ptr
    }
}
extension CancelFlagBridge: Vectorizable {
    public static func vecOfSelfNew() -> UnsafeMutableRawPointer {
        __swift_bridge__$Vec_CancelFlagBridge$new()
    }

    public static func vecOfSelfFree(vecPtr: UnsafeMutableRawPointer) {
        __swift_bridge__$Vec_CancelFlagBridge$drop(vecPtr)
    }

    public static func vecOfSelfPush(vecPtr: UnsafeMutableRawPointer, value: CancelFlagBridge) {
        __swift_bridge__$Vec_CancelFlagBridge$push(vecPtr, {value.isOwned = false; return value.ptr;}())
    }

    public static func vecOfSelfPop(vecPtr: UnsafeMutableRawPointer) -> Optional<Self> {
        let pointer = __swift_bridge__$Vec_CancelFlagBridge$pop(vecPtr)
        if pointer == nil {
            return nil
        } else {
            return (CancelFlagBridge(ptr: pointer!) as! Self)
        }
    }

    public static func vecOfSelfGet(vecPtr: UnsafeMutableRawPointer, index: UInt) -> Optional<CancelFlagBridgeRef> {
        let pointer = __swift_bridge__$Vec_CancelFlagBridge$get(vecPtr, index)
        if pointer == nil {
            return nil
        } else {
            return CancelFlagBridgeRef(ptr: pointer!)
        }
    }

    public static func vecOfSelfGetMut(vecPtr: UnsafeMutableRawPointer, index: UInt) -> Optional<CancelFlagBridgeRefMut> {
        let pointer = __swift_bridge__$Vec_CancelFlagBridge$get_mut(vecPtr, index)
        if pointer == nil {
            return nil
        } else {
            return CancelFlagBridgeRefMut(ptr: pointer!)
        }
    }

    public static func vecOfSelfAsPtr(vecPtr: UnsafeMutableRawPointer) -> UnsafePointer<CancelFlagBridgeRef> {
        UnsafePointer<CancelFlagBridgeRef>(OpaquePointer(__swift_bridge__$Vec_CancelFlagBridge$as_ptr(vecPtr)))
    }

    public static func vecOfSelfLen(vecPtr: UnsafeMutableRawPointer) -> UInt {
        __swift_bridge__$Vec_CancelFlagBridge$len(vecPtr)
    }
}


public class SftpHandleBridge: SftpHandleBridgeRefMut {
    var isOwned: Bool = true

    public override init(ptr: UnsafeMutableRawPointer) {
        super.init(ptr: ptr)
    }

    deinit {
        if isOwned {
            __swift_bridge__$SftpHandleBridge$_free(ptr)
        }
    }
}
public class SftpHandleBridgeRefMut: SftpHandleBridgeRef {
    public override init(ptr: UnsafeMutableRawPointer) {
        super.init(ptr: ptr)
    }
}
public class SftpHandleBridgeRef {
    var ptr: UnsafeMutableRawPointer

    public init(ptr: UnsafeMutableRawPointer) {
        self.ptr = ptr
    }
}
extension SftpHandleBridge: Vectorizable {
    public static func vecOfSelfNew() -> UnsafeMutableRawPointer {
        __swift_bridge__$Vec_SftpHandleBridge$new()
    }

    public static func vecOfSelfFree(vecPtr: UnsafeMutableRawPointer) {
        __swift_bridge__$Vec_SftpHandleBridge$drop(vecPtr)
    }

    public static func vecOfSelfPush(vecPtr: UnsafeMutableRawPointer, value: SftpHandleBridge) {
        __swift_bridge__$Vec_SftpHandleBridge$push(vecPtr, {value.isOwned = false; return value.ptr;}())
    }

    public static func vecOfSelfPop(vecPtr: UnsafeMutableRawPointer) -> Optional<Self> {
        let pointer = __swift_bridge__$Vec_SftpHandleBridge$pop(vecPtr)
        if pointer == nil {
            return nil
        } else {
            return (SftpHandleBridge(ptr: pointer!) as! Self)
        }
    }

    public static func vecOfSelfGet(vecPtr: UnsafeMutableRawPointer, index: UInt) -> Optional<SftpHandleBridgeRef> {
        let pointer = __swift_bridge__$Vec_SftpHandleBridge$get(vecPtr, index)
        if pointer == nil {
            return nil
        } else {
            return SftpHandleBridgeRef(ptr: pointer!)
        }
    }

    public static func vecOfSelfGetMut(vecPtr: UnsafeMutableRawPointer, index: UInt) -> Optional<SftpHandleBridgeRefMut> {
        let pointer = __swift_bridge__$Vec_SftpHandleBridge$get_mut(vecPtr, index)
        if pointer == nil {
            return nil
        } else {
            return SftpHandleBridgeRefMut(ptr: pointer!)
        }
    }

    public static func vecOfSelfAsPtr(vecPtr: UnsafeMutableRawPointer) -> UnsafePointer<SftpHandleBridgeRef> {
        UnsafePointer<SftpHandleBridgeRef>(OpaquePointer(__swift_bridge__$Vec_SftpHandleBridge$as_ptr(vecPtr)))
    }

    public static func vecOfSelfLen(vecPtr: UnsafeMutableRawPointer) -> UInt {
        __swift_bridge__$Vec_SftpHandleBridge$len(vecPtr)
    }
}


public class SshPoolBridge: SshPoolBridgeRefMut {
    var isOwned: Bool = true

    public override init(ptr: UnsafeMutableRawPointer) {
        super.init(ptr: ptr)
    }

    deinit {
        if isOwned {
            __swift_bridge__$SshPoolBridge$_free(ptr)
        }
    }
}
public class SshPoolBridgeRefMut: SshPoolBridgeRef {
    public override init(ptr: UnsafeMutableRawPointer) {
        super.init(ptr: ptr)
    }
}
public class SshPoolBridgeRef {
    var ptr: UnsafeMutableRawPointer

    public init(ptr: UnsafeMutableRawPointer) {
        self.ptr = ptr
    }
}
extension SshPoolBridge: Vectorizable {
    public static func vecOfSelfNew() -> UnsafeMutableRawPointer {
        __swift_bridge__$Vec_SshPoolBridge$new()
    }

    public static func vecOfSelfFree(vecPtr: UnsafeMutableRawPointer) {
        __swift_bridge__$Vec_SshPoolBridge$drop(vecPtr)
    }

    public static func vecOfSelfPush(vecPtr: UnsafeMutableRawPointer, value: SshPoolBridge) {
        __swift_bridge__$Vec_SshPoolBridge$push(vecPtr, {value.isOwned = false; return value.ptr;}())
    }

    public static func vecOfSelfPop(vecPtr: UnsafeMutableRawPointer) -> Optional<Self> {
        let pointer = __swift_bridge__$Vec_SshPoolBridge$pop(vecPtr)
        if pointer == nil {
            return nil
        } else {
            return (SshPoolBridge(ptr: pointer!) as! Self)
        }
    }

    public static func vecOfSelfGet(vecPtr: UnsafeMutableRawPointer, index: UInt) -> Optional<SshPoolBridgeRef> {
        let pointer = __swift_bridge__$Vec_SshPoolBridge$get(vecPtr, index)
        if pointer == nil {
            return nil
        } else {
            return SshPoolBridgeRef(ptr: pointer!)
        }
    }

    public static func vecOfSelfGetMut(vecPtr: UnsafeMutableRawPointer, index: UInt) -> Optional<SshPoolBridgeRefMut> {
        let pointer = __swift_bridge__$Vec_SshPoolBridge$get_mut(vecPtr, index)
        if pointer == nil {
            return nil
        } else {
            return SshPoolBridgeRefMut(ptr: pointer!)
        }
    }

    public static func vecOfSelfAsPtr(vecPtr: UnsafeMutableRawPointer) -> UnsafePointer<SshPoolBridgeRef> {
        UnsafePointer<SshPoolBridgeRef>(OpaquePointer(__swift_bridge__$Vec_SshPoolBridge$as_ptr(vecPtr)))
    }

    public static func vecOfSelfLen(vecPtr: UnsafeMutableRawPointer) -> UInt {
        __swift_bridge__$Vec_SshPoolBridge$len(vecPtr)
    }
}



