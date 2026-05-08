package com.facebook.presto.plugin.clp.metadata;

/**
 * The CLP schema-tree node types used in clp-s archives.
 */
public enum ClpSchemaTreeNodeType {
    Integer((byte)0),
    Float((byte)1),
    ClpString((byte)2),
    VarString((byte)3),
    Boolean((byte)4),
    Object((byte)5),
    UnstructuredArray((byte)6),
    NullValue((byte)7),
    DeprecatedDateString((byte)8),
    StructuredArray((byte)9),
    FormattedFloat((byte)12),
    DictionaryFloat((byte)13),
    Timestamp((byte)14);

    private static final ClpSchemaTreeNodeType[] LOOKUP_TABLE;
    private final byte type;

    ClpSchemaTreeNodeType(byte type) {
        this.type = type;
    }

    public static ClpSchemaTreeNodeType fromType(byte type) {
        if (type < 0 || type >= LOOKUP_TABLE.length || LOOKUP_TABLE[type] == null) {
            throw new IllegalArgumentException("Invalid type code: " + type);
        }
        return LOOKUP_TABLE[type];
    }

    public byte getType() { return type; }

    static {
        byte maxType = 0;
        for (ClpSchemaTreeNodeType nodeType : values()) {
            if (nodeType.type > maxType) {
                maxType = nodeType.type;
            }
        }

        ClpSchemaTreeNodeType[] lookup = new ClpSchemaTreeNodeType[maxType + 1];
        for (ClpSchemaTreeNodeType nodeType : values()) {
            lookup[nodeType.type] = nodeType;
        }

        LOOKUP_TABLE = lookup;
    }
}
