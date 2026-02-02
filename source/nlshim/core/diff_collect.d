module nlshim.core.diff_collect;

import nlshim.core.render.backends : RenderResourceHandle;

struct DifferenceEvaluationRegion {
    int x;
    int y;
    int width;
    int height;
}

struct DifferenceEvaluationResult {
    double red;
    double green;
    double blue;
    double alpha;
    double[16] tileRed;
    double[16] tileGreen;
    double[16] tileBlue;
    double[16] tileAlpha;
}

// placeholders for queue/dx backends; OpenGL implementation lives in diff_collect_impl

private __gshared bool gEnabled;
private __gshared DifferenceEvaluationRegion gRegion;

void rpSetDifferenceEvaluationEnabled(bool enabled) { gEnabled = enabled; }
bool rpDifferenceEvaluationEnabled() { return gEnabled; }
void rpSetDifferenceEvaluationRegion(DifferenceEvaluationRegion region) { gRegion = region; }
DifferenceEvaluationRegion rpGetDifferenceEvaluationRegion() { return gRegion; }
bool rpEvaluateDifference(RenderResourceHandle, int width, int height) { return false; }
bool rpFetchDifferenceResult(out DifferenceEvaluationResult result) { result = DifferenceEvaluationResult.init; return false; }
