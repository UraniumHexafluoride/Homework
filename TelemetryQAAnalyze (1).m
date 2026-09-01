% =============================================================================
% TELEMETRY QA - MAIN ENTRY POINT
% =============================================================================
% Usage:
%   TelemetryQAAnalyze()              - runs full pass/fail analysis, writes
%                                        the color-coded Excel report.
%   TelemetryQAAnalyze('inventory')   - discovery mode only. Scans all files
%                                        and lists every top-level container
%                                        name found (and one level of children
%                                        inside each), with file counts. Does
%                                        NOT evaluate pass/fail or write Excel.
%
% Each LRID number identifies which system a file belongs to (this is the
% source of truth, not the file's internal contents). Only files whose LRID
% is listed in LRID_MAP below are processed; any other LRID_*_EntireRun.mat
% file found in the folder is skipped with a warning, since it's not part
% of the CEU/PDS/UPS group.
%
% CONTAINER SEARCH: the struct named 'ceu' (or 'pds'/'ups') is NOT
% guaranteed to be at the top level of the file - it can be nested inside
% some other container. locatePowerContainers searches the ENTIRE struct
% tree recursively for a field matching the expected word (case-insensitive,
% whole token). Wherever it's found, that's the container that gets
% searched for telemetry.
%
% DATA TYPE HANDLING: struct fields can be scalars, arrays/matrices,
% logicals, strings, or empty. Every captured item gets one of FOUR
% statuses:
%   PASS    - within limits (or no check applies)
%   FAIL    - a fault flag is nonzero, OR a numeric array has a sample
%             outside its own 99% confidence band (see below)
%   REVIEW  - either the value's type couldn't be confidently judged, or a
%             numeric array has samples outside its 95% band but not its
%             99% band (borderline) - a visibility flag, NOT a silent pass
%   SKIPPED - a whole FILE was skipped (LRID unrecognized, or contents
%             didn't match what the LRID claimed)
%
% CONFIDENCE-BAND STATISTICS: for any numeric array field (multiple
% samples, not a single scalar), the mean and standard deviation of that
% field's OWN samples are computed, then two things are checked:
%   - what % of samples fall within a 95% confidence band (mean +/- 1.96 sigma)
%   - what % of samples fall within a 99% confidence band (mean +/- 2.576 sigma)
% Both percentages are shown as their own report columns for every array
% field. A sample outside the 99% band is treated as a real outlier (FAIL);
% outside the 95% band but inside the 99% band is borderline (REVIEW).
function TelemetryQAAnalyze(mode)
    if nargin < 1 || isempty(mode)
        mode = 'analyze';
    end

    files = dir('LRID_*_EntireRun.mat');
    if isempty(files)
        warning('No LRID telemetry files found matching pattern LRID_*_EntireRun.mat.');
        return;
    end

    % LRID number -> expected system type. Add more entries here as your
    % group grows. Values must match a struct name found SOMEWHERE inside
    % the corresponding file (not necessarily at the top level).
    LRID_MAP = containers.Map( ...
        {'24566', '24578', '24572'}, ...
        {'UPS',   'CEU',   'PDS'});

    if strcmpi(mode, 'inventory')
        runInventory(files, LRID_MAP);
        return;
    end

    % 1. Initialization
    analysisDir = get_analysis_dir();
    excelReportPath = fullfile(analysisDir, 'Telemetry_PassFail_Report.xlsx');

    reportHeader = { ...
        'File / Section', 'Telemetry Path', 'Measured Value', 'Unit', 'Data Type', ...
        '95% CI (%% within)', '99% CI (%% within)', 'Relevance Category', 'Status' ...
    };

    % For CRITICAL_FAULT fields (fault/failed/trip/alarm/etc in the name),
    % the code needs to know whether 0 or 1 means "good" - this is NOT
    % always the same across fields (a "fault" flag is usually 0=good, but
    % an "online"/"enabled" style flag is usually 1=good). Rather than
    % guess, unconfigured fields are marked REVIEW instead of PASS/FAIL.
    % Add entries here as you figure out each field's actual convention - 
    % the key is matched as a substring against the field's own name
    % (case-insensitive), e.g.:
    %   FAULT_POLARITY('fault')  = 'ZeroIsGood';  % 0 = no fault = PASS
    %   FAULT_POLARITY('online') = 'OneIsGood';   % 1 = online = PASS
    FAULT_POLARITY = containers.Map('KeyType', 'char', 'ValueType', 'char');

    % 2. Defined Domain Keywords (Isolated) - applied within whatever
    % container the file resolves to, regardless of system type.
    domains.Thermal = {'temp', 'temperature', 'degc', 'degf', 'kelvin', 'coolant', 'flow'};
    domains.Power   = {'voltage', 'volt', 'current', 'power', 'soc', 'freq', 'pds', 'ups'};
    domains.Faults  = {'fault', 'failed', 'trip', 'alarm', 'err', 'overtemp', 'leak'};

    % Data accumulators. allData feeds the "All" sheet; typeData holds a
    % separate table per system (CEU/PDS/UPS) for its own dedicated sheet.
    allData = reportHeader;
    groupNames = unique(values(LRID_MAP), 'stable');
    typeData = containers.Map('KeyType', 'char', 'ValueType', 'any');
    for g = 1:length(groupNames)
        typeData(groupNames{g}) = reportHeader;
    end

    % Terminal summary tracking - counts plus a per-group (CEU/PDS/UPS)
    % listing of every item, printed after the loop finishes.
    totalPass = 0;
    totalFail = 0;
    totalReview = 0;
    totalSkipped = 0;
    groupEntries = containers.Map('KeyType', 'char', 'ValueType', 'any');
    for g = 1:length(groupNames)
        groupEntries(groupNames{g}) = {};
    end
    unrecognizedEntries = {};

    % 3. Iterate through files
    for fIdx = 1:length(files)
        fileName = files(fIdx).name;

        lridNum = extractLRID(fileName);
        if isempty(lridNum)
            warning('File %s: could not parse an LRID number from the filename, skipping.', fileName);
            allData(end+1, :) = { ...
                fileName, 'N/A', 'N/A', 'N/A', 'N/A', 'N/A', 'N/A', 'FILE_SKIPPED', 'SKIPPED: no LRID parsed' ...
            }; %#ok<AGROW>
            totalSkipped = totalSkipped + 1;
            unrecognizedEntries{end+1} = sprintf('%s : SKIPPED (no LRID parsed)', fileName); %#ok<AGROW>
            continue;
        end

        if ~isKey(LRID_MAP, lridNum)
            warning('File %s: LRID %s is not in LRID_MAP (not CEU/PDS/UPS), skipping.', fileName, lridNum);
            allData(end+1, :) = { ...
                fileName, 'N/A', 'N/A', 'N/A', 'N/A', 'N/A', 'N/A', 'FILE_SKIPPED', sprintf('SKIPPED: LRID %s not in group', lridNum) ...
            }; %#ok<AGROW>
            totalSkipped = totalSkipped + 1;
            unrecognizedEntries{end+1} = sprintf('%s : SKIPPED (LRID %s not in group)', fileName, lridNum); %#ok<AGROW>
            continue;
        end

        expectedType = LRID_MAP(lridNum);

        raw = load(fileName);
        cleanName = erase(fileName, '.mat');

        % Search the ENTIRE file (any depth) for a struct named like
        % expectedType - not just the top level.
        containerMatches = locatePowerContainers(raw, expectedType);
        if isempty(containerMatches)
            warning('File %s: LRID %s is mapped to "%s" but no matching struct was found anywhere inside. Skipping this file - check for a mismatch.', ...
                fileName, lridNum, expectedType);
            mismatchRow = { ...
                cleanName, 'N/A', 'N/A', 'N/A', 'N/A', 'N/A', 'N/A', 'FILE_MISMATCH', ...
                sprintf('SKIPPED: LRID %s expected %s, not found inside', lridNum, expectedType) ...
            };
            allData(end+1, :) = mismatchRow; %#ok<AGROW>
            tRows = typeData(expectedType);
            tRows(end+1, :) = mismatchRow;
            typeData(expectedType) = tRows;

            totalSkipped = totalSkipped + 1;
            entries = groupEntries(expectedType);
            entries{end+1} = sprintf('%s : SKIPPED (expected %s not found inside)', cleanName, expectedType);
            groupEntries(expectedType) = entries;
            continue;
        end

        for cIdx = 1:length(containerMatches)
            containerName = containerMatches{cIdx}.path;   % e.g. 'someWrapper.ceu'
            containerData = containerMatches{cIdx}.value;

            % Capture EVERY field inside the container in one pass - domain
            % keywords below are for LABELING only, not for filtering.
            searchResults = searchTelemetryWorkspace(containerData, {}, containerName);

            for k = 1:length(searchResults)
                res = searchResults(k);
                if strcmp(res.relevance, 'METADATA_IGNORE')
                    continue;
                end

                dName = classifyDomain(res.path, domains);

                [statusStr, pct95Str, pct99Str] = evaluateItemStatus(res, FAULT_POLARITY);
                switch statusStr
                    case 'PASS'
                        totalPass = totalPass + 1;
                    case 'FAIL'
                        totalFail = totalFail + 1;
                    case 'REVIEW'
                        totalReview = totalReview + 1;
                end

                sectionTag = sprintf('%s (LRID %s / %s) [%s]', cleanName, lridNum, expectedType, dName);
                dataRow = { ...
                    sectionTag, res.path, res.displayValue, res.unit, res.dataType, ...
                    pct95Str, pct99Str, res.relevance, statusStr ...
                };
                allData(end+1, :) = dataRow; %#ok<AGROW>
                tRows = typeData(expectedType);
                tRows(end+1, :) = dataRow;
                typeData(expectedType) = tRows;

                entries = groupEntries(expectedType);
                entries{end+1} = sprintf('%s : %s (%s) [%s] {%s} 95%%=%s 99%%=%s', ...
                    cleanName, statusStr, res.path, dName, res.dataType, pct95Str, pct99Str);
                groupEntries(expectedType) = entries;
            end
        end
    end

    % 4. Print terminal summary
    printSummaryReport(totalPass, totalFail, totalReview, totalSkipped, groupEntries, unrecognizedEntries);

    % 5. Write the 5-sheet Excel report (CEU / PDS / UPS / All / Summary)
    % with PASS=green, FAIL=red, SKIPPED=yellow, REVIEW=blue highlighting.
    writeExcelReport(excelReportPath, allData, typeData, groupNames, totalPass, totalFail, totalReview, totalSkipped);

    % 6. Execute Core Test Suites
    CapabilityTestSuite();
    SafetyCriticalMetrics();

    CheckCompletion();
end


% =============================================================================
% TERMINAL SUMMARY REPORT
% =============================================================================
function printSummaryReport(totalPass, totalFail, totalReview, totalSkipped, groupEntries, unrecognizedEntries)
    grandTotal = totalPass + totalFail + totalReview + totalSkipped;
    pct = computePercentages([totalPass, totalFail, totalReview, totalSkipped], grandTotal);

    fprintf('\n============================================================\n');
    fprintf('  TELEMETRY QA SUMMARY\n');
    fprintf('============================================================\n');
    fprintf('  Total PASS:    %d  (%.1f%%)\n', totalPass, pct(1));
    fprintf('  Total FAIL:    %d  (%.1f%%)\n', totalFail, pct(2));
    fprintf('  Total REVIEW:  %d  (%.1f%%)  <- ambiguous type OR array with borderline (95%%-99%%) outliers\n', totalReview, pct(3));
    fprintf('  Total SKIPPED: %d  (%.1f%%)\n', totalSkipped, pct(4));
    fprintf('============================================================\n');

    groupNames = keys(groupEntries);
    for g = 1:length(groupNames)
        gName = groupNames{g};
        entries = groupEntries(gName);
        fprintf('\n--- %s (%d item(s)) ---\n', gName, length(entries));
        for e = 1:length(entries)
            fprintf('  %s\n', entries{e});
        end
    end

    if ~isempty(unrecognizedEntries)
        fprintf('\n--- Unrecognized Files (%d) ---\n', length(unrecognizedEntries));
        for e = 1:length(unrecognizedEntries)
            fprintf('  %s\n', unrecognizedEntries{e});
        end
    end
    fprintf('\n');
end

function pct = computePercentages(counts, grandTotal)
    if grandTotal == 0
        pct = zeros(size(counts));
    else
        pct = 100 * counts / grandTotal;
    end
end


% =============================================================================
% LRID NUMBER EXTRACTOR
% =============================================================================
function lridNum = extractLRID(fileName)
    tok = regexp(fileName, 'LRID_(\d+)_EntireRun', 'tokens', 'once');
    if isempty(tok)
        lridNum = '';
    else
        lridNum = tok{1};
    end
end


% =============================================================================
% CONTAINER LOCATOR (recursive - searches the whole file, any depth)
% =============================================================================
function matches = locatePowerContainers(S, wantedName)
    matches = findContainerRecursive(S, wantedName, '');
end

function matches = findContainerRecursive(S, wantedName, parentPath)
    matches = {};

    if iscell(S)
        for c = 1:numel(S)
            cellPath = sprintf('%s{%d}', parentPath, c);
            matches = [matches, findContainerRecursive(S{c}, wantedName, cellPath)]; %#ok<AGROW>
        end
        return;
    end

    if ~isstruct(S), return; end

    fnames = fieldnames(S);
    for i = 1:length(fnames)
        fieldName = fnames{i};
        if isempty(parentPath)
            currentPath = fieldName;
        else
            currentPath = [parentPath, '.', fieldName];
        end
        fieldVal = S.(fieldName);

        if isWholeTokenMatch(fieldName, wantedName)
            m.path = currentPath;
            m.value = fieldVal;
            matches{end+1} = m; %#ok<AGROW>
            continue;
        end

        if isstruct(fieldVal)
            for k = 1:numel(fieldVal)
                if numel(fieldVal) > 1
                    arrayPath = sprintf('%s(%d)', currentPath, k);
                else
                    arrayPath = currentPath;
                end
                matches = [matches, findContainerRecursive(fieldVal(k), wantedName, arrayPath)]; %#ok<AGROW>
            end
        elseif iscell(fieldVal)
            matches = [matches, findContainerRecursive(fieldVal, wantedName, currentPath)]; %#ok<AGROW>
        end
    end
end

function tf = isWholeTokenMatch(fieldName, token)
    pattern = ['(?<![A-Za-z])' token '(?![A-Za-z])'];
    tf = ~isempty(regexpi(fieldName, pattern, 'once'));
end


% =============================================================================
% INVENTORY / DISCOVERY MODE (local helper - call via TelemetryQAAnalyze('inventory'))
% =============================================================================
function runInventory(files, LRID_MAP)
    fprintf('\n=== FILENAME / LRID CHECK ===\n\n');
    for fIdx = 1:length(files)
        fileName = files(fIdx).name;
        lridNum = extractLRID(fileName);
        if isempty(lridNum)
            fprintf('%s  -> could not parse LRID number\n', fileName);
        elseif isKey(LRID_MAP, lridNum)
            fprintf('%s  -> LRID %s, expected type: %s\n', fileName, lridNum, LRID_MAP(lridNum));
        else
            fprintf('%s  -> LRID %s, NOT in LRID_MAP (not CEU/PDS/UPS)\n', fileName, lridNum);
        end
    end

    topLevelCounts = containers.Map('KeyType', 'char', 'ValueType', 'double');
    childMap = containers.Map('KeyType', 'char', 'ValueType', 'any');

    for fIdx = 1:length(files)
        fileName = files(fIdx).name;
        raw = load(fileName);
        topNames = fieldnames(raw);

        for i = 1:length(topNames)
            tName = topNames{i};

            if isKey(topLevelCounts, tName)
                topLevelCounts(tName) = topLevelCounts(tName) + 1;
            else
                topLevelCounts(tName) = 1;
                childMap(tName) = containers.Map('KeyType', 'char', 'ValueType', 'double');
            end

            val = raw.(tName);
            if isstruct(val) && numel(val) >= 1
                childNames = fieldnames(val(1));
                cMap = childMap(tName);
                for j = 1:length(childNames)
                    cName = childNames{j};
                    if isKey(cMap, cName)
                        cMap(cName) = cMap(cName) + 1;
                    else
                        cMap(cName) = 1;
                    end
                end
                childMap(tName) = cMap;
            end
        end
    end

    fprintf('\n=== STRUCT CONTENTS: %d file(s) scanned ===\n\n', length(files));
    topNames = keys(topLevelCounts);
    for i = 1:length(topNames)
        tName = topNames{i};
        fprintf('%s  (present in %d/%d files)\n', tName, topLevelCounts(tName), length(files));

        cMap = childMap(tName);
        cNames = keys(cMap);
        for j = 1:length(cNames)
            fprintf('    - %s  (%d file(s))\n', cNames{j}, cMap(cNames{j}));
        end
    end
    fprintf('\nNote: this listing only shows the TOP two levels of each file.\n');
    fprintf('The real analysis search (locatePowerContainers) goes to any depth,\n');
    fprintf('so it can find CEU/PDS/UPS even if this quick-look doesn''t show it.\n\n');
end


% =============================================================================
% DOMAIN LABELER (labeling only - does NOT filter what gets included)
% =============================================================================
function dLabel = classifyDomain(fieldPath, domains)
    parts = regexp(fieldPath, '[.\(\)\{\}]', 'split');
    leafName = parts{end};
    fLower = lower(leafName);

    domainNames = fieldnames(domains);
    for d = 1:length(domainNames)
        kWords = domains.(domainNames{d});
        for k = 1:length(kWords)
            if contains(fLower, lower(kWords{k}))
                dLabel = domainNames{d};
                return;
            end
        end
    end
    dLabel = 'Other';
end


% =============================================================================
% DATA TYPE CLASSIFIER
% =============================================================================
function info = classifyValueType(fieldVal)
    info.isEmptyVal   = isempty(fieldVal);
    info.isLogicalVal = islogical(fieldVal);
    info.isNumericVal = isnumeric(fieldVal);
    info.isCharVal    = ischar(fieldVal) || isstring(fieldVal);
    info.isScalar     = isscalar(fieldVal);

    if info.isEmptyVal
        info.typeLabel = 'EMPTY';
    elseif info.isLogicalVal
        if info.isScalar
            info.typeLabel = 'logical (scalar)';
        else
            info.typeLabel = sprintf('logical [%s]', sizeLabel(fieldVal));
        end
    elseif info.isNumericVal
        if info.isScalar
            info.typeLabel = sprintf('%s (scalar)', class(fieldVal));
        else
            info.typeLabel = sprintf('%s [%s]', class(fieldVal), sizeLabel(fieldVal));
        end
    elseif info.isCharVal
        info.typeLabel = 'char/string';
    else
        info.typeLabel = class(fieldVal);
    end
end

function s = sizeLabel(val)
    sz = size(val);
    parts = arrayfun(@(x) num2str(x), sz, 'UniformOutput', false);
    s = strjoin(parts, 'x');
end

function dv = formatDisplayValue(fieldVal, typeInfo)
    if typeInfo.isEmptyVal
        dv = '[empty]';
    elseif typeInfo.isLogicalVal
        if typeInfo.isScalar
            dv = mat2str(fieldVal);
        else
            dv = sprintf('N=%d, true=%d, false=%d', numel(fieldVal), sum(fieldVal(:)), sum(~fieldVal(:)));
        end
    elseif typeInfo.isNumericVal
        if typeInfo.isScalar
            dv = fieldVal;
        else
            v = double(fieldVal(:));
            dv = sprintf('N=%d min=%.4g max=%.4g mean=%.4g', numel(v), min(v), max(v), mean(v));
        end
    elseif typeInfo.isCharVal
        dv = char(fieldVal);
    else
        dv = sprintf('<%s, unrecognized type>', class(fieldVal));
    end
end


% =============================================================================
% CONFIDENCE-BAND STATISTICS (95% / 99%)
% =============================================================================
function info = computeConfidenceBand(vals)
    Z95 = 1.959964;
    Z99 = 2.575829;

    vals = double(vals(:));
    n = numel(vals);
    info.n = n;
    info.mean = mean(vals);
    info.std = std(vals);

    if n < 2 || info.std == 0
        info.pctWithin95 = 100;
        info.pctWithin99 = 100;
        info.outlier99Count = 0;
        return;
    end

    low95 = info.mean - Z95 * info.std;
    high95 = info.mean + Z95 * info.std;
    low99 = info.mean - Z99 * info.std;
    high99 = info.mean + Z99 * info.std;

    within95 = vals >= low95 & vals <= high95;
    within99 = vals >= low99 & vals <= high99;

    info.pctWithin95 = 100 * sum(within95) / n;
    info.pctWithin99 = 100 * sum(within99) / n;
    info.outlier99Count = sum(~within99);
end


% =============================================================================
% FAULT POLARITY LOOKUP
% =============================================================================
function polarity = lookupFaultPolarity(fieldPath, FAULT_POLARITY)
    parts = regexp(fieldPath, '[.\(\)\{\}]', 'split');
    leafName = lower(parts{end});
    polarity = '';

    knownKeys = keys(FAULT_POLARITY);
    for i = 1:length(knownKeys)
        if contains(leafName, lower(knownKeys{i}))
            polarity = FAULT_POLARITY(knownKeys{i});
            return;
        end
    end
end


% =============================================================================
% ITEM EVALUATION UTILITY
% =============================================================================
function [statusStr, pct95Str, pct99Str] = evaluateItemStatus(res, FAULT_POLARITY)
    statusStr = 'PASS';
    pct95Str = 'N/A';
    pct99Str = 'N/A';

    if strcmp(res.relevance, 'CRITICAL_FAULT')
        if ~(res.isLogicalVal || (res.isNumericVal && ~res.isEmptyVal))
            statusStr = 'REVIEW';
            return;
        end

        polarity = lookupFaultPolarity(res.path, FAULT_POLARITY);
        if isempty(polarity)
            statusStr = 'REVIEW';
            return;
        end

        vals = res.rawValue(:);
        if strcmp(polarity, 'ZeroIsGood')
            if any(vals ~= 0)
                statusStr = 'FAIL';
            end
        else
            if any(vals == 0)
                statusStr = 'FAIL';
            end
        end

    elseif strcmp(res.relevance, 'PRIMARY_TELEMETRY')
        if res.isEmptyVal || ~(res.isNumericVal || res.isLogicalVal)
            statusStr = 'REVIEW';
            return;
        end

        if res.isScalar
            statusStr = 'PASS';
            return;
        end

        ci = computeConfidenceBand(res.rawValue);
        pct95Str = sprintf('%.1f%%', ci.pctWithin95);
        pct99Str = sprintf('%.1f%%', ci.pctWithin99);

        if ci.outlier99Count > 0
            statusStr = 'FAIL';
        elseif ci.pctWithin95 < 100
            statusStr = 'REVIEW';
        else
            statusStr = 'PASS';
        end
    end
end


% =============================================================================
% EXCEL WRITER & ACTIVEX COLOR FORMATTING ENGINE (5 sheets)
% =============================================================================
function writeExcelReport(filePath, allData, typeData, groupNames, totalPass, totalFail, totalReview, totalSkipped)
    for g = 1:length(groupNames)
        writecell(typeData(groupNames{g}), filePath, 'Sheet', groupNames{g});
    end

    writecell(allData, filePath, 'Sheet', 'All');

    grandTotal = totalPass + totalFail + totalReview + totalSkipped;
    pct = computePercentages([totalPass, totalFail, totalReview, totalSkipped], grandTotal);
    summaryData = { ...
        'Metric', 'Count', 'Percentage'; ...
        'Total PASS', totalPass, sprintf('%.1f%%', pct(1)); ...
        'Total FAIL', totalFail, sprintf('%.1f%%', pct(2)); ...
        'Total REVIEW', totalReview, sprintf('%.1f%%', pct(3)); ...
        'Total SKIPPED', totalSkipped, sprintf('%.1f%%', pct(4)) ...
    };
    writecell(summaryData, filePath, 'Sheet', 'Summary');

    dataSheetNames = [groupNames, {'All'}];

    try
        Excel = actxserver('Excel.Application');
        Excel.Visible = false;
        Workbook = Excel.Workbooks.Open(filePath);

        for s = 1:length(dataSheetNames)
            sheetName = dataSheetNames{s};
            Sheet = Workbook.Worksheets.Item(sheetName);
            numRows = Sheet.UsedRange.Rows.Count;

            for row = 2:numRows
                statusValue = Sheet.Range(sprintf('I%d', row)).Value;
                rowRange = Sheet.Range(sprintf('A%d:I%d', row, row));
                cellRef = sprintf('I%d', row);

                if strcmp(statusValue, 'PASS')
                    rowRange.Interior.Color = hex2dec('C6EFCE');
                    Sheet.Range(cellRef).Font.Color = hex2dec('006100');
                elseif strcmp(statusValue, 'FAIL')
                    rowRange.Interior.Color = hex2dec('FFC7CE');
                    Sheet.Range(cellRef).Font.Color = hex2dec('9C0006');
                elseif strcmp(statusValue, 'REVIEW')
                    rowRange.Interior.Color = hex2dec('DDEBF7');
                    Sheet.Range(cellRef).Font.Color = hex2dec('1F4E78');
                elseif ischar(statusValue) && startsWith(statusValue, 'SKIPPED')
                    rowRange.Interior.Color = hex2dec('FFEB9C');
                    Sheet.Range(cellRef).Font.Color = hex2dec('9C6500');
                end
            end

            Sheet.Columns.AutoFit();
        end

        SummarySheet = Workbook.Worksheets.Item('Summary');
        SummarySheet.Range('A2:C2').Interior.Color = hex2dec('C6EFCE');
        SummarySheet.Range('A3:C3').Interior.Color = hex2dec('FFC7CE');
        SummarySheet.Range('A4:C4').Interior.Color = hex2dec('DDEBF7');
        SummarySheet.Range('A5:C5').Interior.Color = hex2dec('FFEB9C');
        SummarySheet.Columns.AutoFit();

        Workbook.Save();
        Workbook.Close(false);
        Excel.Quit();
        Excel.delete();
        fprintf('\n[ SUCCESS ] Formatted Excel report generated at: %s\n', filePath);
    catch err
        warning('Excel formatting engine encounter: %s. Raw Excel file written without color formatting.', err.message);
    end
end


% =============================================================================
% WORKSPACE SEARCH ENGINE & HELPERS
% =============================================================================
function searchResults = searchTelemetryWorkspace(S, searchKeywords, parentPath)
    if nargin < 3, parentPath = ''; end
    searchResults = struct('path', {}, 'rawValue', {}, 'displayValue', {}, 'unit', {}, ...
        'relevance', {}, 'dataType', {}, 'isEmptyVal', {}, 'isLogicalVal', {}, ...
        'isNumericVal', {}, 'isCharVal', {}, 'isScalar', {});

    if iscell(S)
        for c = 1:numel(S)
            cellPath = sprintf('%s{%d}', parentPath, c);
            subResults = searchTelemetryWorkspace(S{c}, searchKeywords, cellPath);
            searchResults = [searchResults, subResults]; %#ok<AGROW>
        end
        return;
    end

    if ~isstruct(S), return; end

    fnames = fieldnames(S);
    for i = 1:length(fnames)
        fieldName = fnames{i};
        if isempty(parentPath)
            currentPath = fieldName;
        else
            currentPath = [parentPath, '.', fieldName];
        end
        fieldVal = S.(fieldName);

        isMatch = false;
        if isempty(searchKeywords)
            isMatch = true;
        else
            for k = 1:length(searchKeywords)
                if contains(lower(fieldName), lower(searchKeywords{k}))
                    isMatch = true;
                    break;
                end
            end
        end

        if isMatch && ~isstruct(fieldVal) && ~iscell(fieldVal)
            relevance = classifyFieldRelevance(fieldName);
            [~, unitStr] = resolveAndNormalizeUnits(fieldName, fieldVal);
            typeInfo = classifyValueType(fieldVal);
            displayVal = formatDisplayValue(fieldVal, typeInfo);

            idx = length(searchResults) + 1;
            searchResults(idx).path         = currentPath;
            searchResults(idx).rawValue     = fieldVal;
            searchResults(idx).displayValue = displayVal;
            searchResults(idx).unit         = unitStr;
            searchResults(idx).relevance    = relevance;
            searchResults(idx).dataType     = typeInfo.typeLabel;
            searchResults(idx).isEmptyVal   = typeInfo.isEmptyVal;
            searchResults(idx).isLogicalVal = typeInfo.isLogicalVal;
            searchResults(idx).isNumericVal = typeInfo.isNumericVal;
            searchResults(idx).isCharVal    = typeInfo.isCharVal;
            searchResults(idx).isScalar     = typeInfo.isScalar;
        end

        if isstruct(fieldVal)
            for k = 1:numel(fieldVal)
                if numel(fieldVal) > 1
                    arrayPath = sprintf('%s(%d)', currentPath, k);
                else
                    arrayPath = currentPath;
                end
                subResults = searchTelemetryWorkspace(fieldVal(k), searchKeywords, arrayPath);
                searchResults = [searchResults, subResults]; %#ok<AGROW>
            end
        elseif iscell(fieldVal)
            subResults = searchTelemetryWorkspace(fieldVal, searchKeywords, currentPath);
            searchResults = [searchResults, subResults]; %#ok<AGROW>
        end
    end
end

function relevance = classifyFieldRelevance(fieldName)
    fLower = lower(fieldName);
    if contains(fLower, {'fault', 'failed', 'trip', 'overtemp', 'leak', 'breaker', 'alarm', 'critical'})
        relevance = 'CRITICAL_FAULT';
    elseif contains(fLower, {'warning', 'condition', 'state', 'status', 'mode', 'enable', 'bypass'})
        relevance = 'OPERATIONAL_STATE';
    elseif contains(fLower, {'temp', 'pressure', 'flow', 'voltage', 'current', 'power', 'soc', 'freq'})
        relevance = 'PRIMARY_TELEMETRY';
    elseif contains(fLower, {'time', 'stamp', 'index', 'counter', 'crc', 'checksum', 'reserved', 'spare'}) || isIdLikeField(fieldName)
        relevance = 'METADATA_IGNORE';
    else
        relevance = 'SECONDARY_TELEMETRY';
    end
end

function tf = isIdLikeField(fieldName)
    pattern = '(^|[_\d])[Ii][Dd]([_\d]|$)';
    tf = ~isempty(regexp(fieldName, pattern, 'once'));
end

function [normalizedValue, unitStr] = resolveAndNormalizeUnits(fieldName, rawValue)
    fLower = lower(fieldName);
    normalizedValue = rawValue;
    unitStr = 'UNKNOWN';
    if ~isnumeric(rawValue) || isempty(rawValue)
        unitStr = 'NON_NUMERIC';
        return;
    end
    if contains(fLower, {'temp', 'temperature'})
        if contains(fLower, {'_degc', '_celsius', '_c'})
            unitStr = 'Celsius';
        elseif contains(fLower, {'_degf', '_fahrenheit', '_f'})
            unitStr = 'Fahrenheit';
        elseif contains(fLower, {'_k', '_kelvin'})
            unitStr = 'Kelvin';
        else
            unitStr = 'Celsius (Assumed)';
        end
    elseif contains(fLower, {'pressure', 'press', 'airpressure'})
        if contains(fLower, {'_psi'})
            unitStr = 'PSI';
        elseif contains(fLower, {'_kpa'})
            unitStr = 'kPa';
        elseif contains(fLower, {'_bar'})
            unitStr = 'Bar';
        else
            unitStr = 'PSI (Assumed)';
        end
    elseif contains(fLower, {'voltage', 'volt', 'v_'})
        if contains(fLower, {'_mv', 'millivolt'})
            unitStr = 'mV';
        elseif contains(fLower, {'_kv', 'kilovolt'})
            unitStr = 'kV';
        else
            unitStr = 'Volts';
        end
    elseif contains(fLower, {'flow', 'flowrate'})
        if contains(fLower, {'_lpm'})
            unitStr = 'LPM';
        else
            unitStr = 'GPM';
        end
    elseif contains(fLower, {'soc', 'percent', 'charge'})
        unitStr = 'Percentage (%)';
    elseif contains(fLower, {'fault', 'warning', 'failed', 'leak', 'status', 'state'})
        unitStr = 'Boolean / Bitfield Flag';
    end
end
