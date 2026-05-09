package com.facebook.presto.plugin.clp.split;

import java.util.List;

import com.facebook.presto.plugin.clp.ClpSplit;
import com.facebook.presto.plugin.clp.ClpTableLayoutHandle;

/**
 * A provider for splits from a CLP dataset.
 */
public interface ClpSplitProvider {
    /**
     * @param clpTableLayoutHandle the table layout handle
     * @return the list of splits for the specified table layout
     */
    List<ClpSplit> listSplits(ClpTableLayoutHandle clpTableLayoutHandle);
}
