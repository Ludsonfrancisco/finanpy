import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../../design_system/lar_colors.dart';
import '../../domain/cards_models.dart';

final class CardItemWidget extends StatelessWidget {
  const CardItemWidget({
    required this.card,
    this.isSelected = false,
    this.onTap,
    super.key,
  });

  final CreditCardModel card;
  final bool isSelected;
  final VoidCallback? onTap;

  Color _parseColor(String hex) {
    try {
      final buffer = StringBuffer();
      if (hex.length == 6 || hex.length == 7) buffer.write('ff');
      buffer.write(hex.replaceFirst('#', ''));
      return Color(int.parse(buffer.toString(), radix: 16));
    } catch (_) {
      return LarColors.mineral;
    }
  }

  @override
  Widget build(BuildContext context) {
    final cardColor = _parseColor(card.color);
    final currencyFmt = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: 300,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(22),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              cardColor,
              const Color(0xFF0F1714),
            ],
          ),
          border: Border.all(
            color: isSelected ? LarColors.mineralOnDark : Colors.white.withAlpha(30),
            width: isSelected ? 2 : 1,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withAlpha(80),
              blurRadius: 16,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            // Top row: Chip and Brand
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                // EMV Chip
                Container(
                  width: 36,
                  height: 26,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(6),
                    gradient: const LinearGradient(
                      colors: [Color(0xFFFDE68A), Color(0xFFF59E0B)],
                    ),
                    border: Border.all(color: const Color(0xFFD97706), width: 0.8),
                  ),
                ),
                // Brand pill
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.black.withAlpha(100),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.white.withAlpha(30)),
                  ),
                  child: Text(
                    card.brandDisplay.toUpperCase(),
                    style: const TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1.2,
                      color: Colors.white,
                    ),
                  ),
                ),
              ],
            ),

            // Middle: Name and details
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  card.name,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                    letterSpacing: 0.5,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  'Titular: ${card.financialOwnerName}${card.lastDigits.isNotEmpty ? ' •••• ${card.lastDigits}' : ''}',
                  style: TextStyle(
                    fontSize: 11,
                    color: Colors.white.withAlpha(180),
                  ),
                ),
              ],
            ),

            // Bottom: Limit and Dates
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(
                        'Disponível: ${currencyFmt.format(card.availableLimit)}',
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      '${card.limitUsagePercent.toStringAsFixed(0)}% usado',
                      style: TextStyle(
                        fontSize: 10,
                        color: Colors.white.withAlpha(160),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: (card.limitUsagePercent / 100).clamp(0.0, 1.0),
                    minHeight: 4,
                    backgroundColor: Colors.black.withAlpha(80),
                    valueColor: const AlwaysStoppedAnimation<Color>(LarColors.champagne),
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Fecha dia ${card.closingDay}',
                      style: TextStyle(fontSize: 10, color: Colors.white.withAlpha(180)),
                    ),
                    Text(
                      'Vence dia ${card.dueDay}',
                      style: TextStyle(fontSize: 10, color: Colors.white.withAlpha(180)),
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
