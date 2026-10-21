import DesignTokens

/// Где начинается текст строки в стеклянной секции DesignKit 8.0.0: разделитель — под ним.
/// Метка кнопки или ссылки не передаёт отступ наружу, поэтому его ставят на саму кнопку.
/// Для `ItemRow` с `.symbol` — `ItemRowStyle.standard.symbolDividerInset` из DesignKit (8.1.0).
enum ItemRowMetrics {
    /// После аватара `PersonRow` (40) и промежутка.
    static let symbolInset = AppIconSize.xxl + AppSpacing.md
}
