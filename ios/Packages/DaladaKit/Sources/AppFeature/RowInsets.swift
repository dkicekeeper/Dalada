import DesignTokens

/// Где начинается текст строки в стеклянной секции DesignKit 8.0.0: разделитель — под ним.
/// Метка кнопки или ссылки не передаёт отступ наружу, поэтому его ставят на саму кнопку.
enum ItemRowMetrics {
    /// После значка на круге (`ItemRow(leading: .symbol)`, аватар `PersonRow`) и промежутка.
    static let symbolInset = AppIconSize.xxl + AppSpacing.md
}
