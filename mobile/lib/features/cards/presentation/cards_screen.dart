import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../../design_system/lar_colors.dart';
import '../../../../design_system/lar_spacing.dart';
import '../../accounts/data/accounts_repository.dart';
import '../../accounts/domain/accounts_models.dart';
import '../../categories/data/categories_repository.dart';
import '../../categories/domain/categories_models.dart';
import '../../home/domain/home_snapshot.dart';
import '../application/cards_controller.dart';
import '../domain/cards_models.dart';
import 'widgets/card_expense_sheet.dart';
import 'widgets/card_form_sheet.dart';
import 'widgets/card_item_widget.dart';
import 'widgets/pay_invoice_sheet.dart';

final class CardsScreen extends StatefulWidget {
  const CardsScreen({
    required this.controller,
    this.accountsRepository,
    this.categoriesRepository,
    super.key,
  });

  final CardsController controller;
  final AccountsRepository? accountsRepository;
  final CategoriesRepository? categoriesRepository;

  @override
  State<CardsScreen> createState() => _CardsScreenState();
}

final class _CardsScreenState extends State<CardsScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  List<AccountItem> _accounts = [];
  List<CategoryItem> _categories = [];

  final List<String> _ptMonths = [
    '', 'Janeiro', 'Fevereiro', 'Março', 'Abril', 'Maio', 'Junho',
    'Julho', 'Agosto', 'Setembro', 'Outubro', 'Novembro', 'Dezembro'
  ];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging) {
        widget.controller.setActiveTab(_tabController.index);
      }
    });

    widget.controller.addListener(_onControllerChanged);
    widget.controller.start();
    _loadDependencies();
  }

  @override
  void dispose() {
    _tabController.dispose();
    widget.controller.removeListener(_onControllerChanged);
    super.dispose();
  }

  void _onControllerChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _loadDependencies() async {
    if (widget.accountsRepository != null) {
      try {
        final stream = widget.accountsRepository!.watchAccounts(const OwnerScope.household());
        final first = await stream.first;
        if (mounted) setState(() => _accounts = first.accounts);
      } catch (_) {}
    }
    if (widget.categoriesRepository != null) {
      try {
        final stream = widget.categoriesRepository!.watchCategories();
        final first = await stream.first;
        if (mounted) setState(() => _categories = first.categories);
      } catch (_) {}
    }
  }

  void _previousMonth() {
    final state = widget.controller.state;
    var m = state.selectedMonth - 1;
    var y = state.selectedYear;
    if (m < 1) {
      m = 12;
      y--;
    }
    widget.controller.selectMonthYear(m, y);
  }

  void _nextMonth() {
    final state = widget.controller.state;
    var m = state.selectedMonth + 1;
    var y = state.selectedYear;
    if (m > 12) {
      m = 1;
      y++;
    }
    widget.controller.selectMonthYear(m, y);
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.controller.state;

    return Scaffold(
      backgroundColor: const Color(0xFF0C1311),
      body: SafeArea(
        child: state.isLoading && state.cards.isEmpty
            ? const Center(child: CircularProgressIndicator(color: LarColors.mineral))
            : RefreshIndicator(
                onRefresh: widget.controller.loadCards,
                color: LarColors.mineral,
                child: SingleChildScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Header
                      _buildHeader(state),
                      const SizedBox(height: LarSpacing.md),

                      // Owner Selector
                      _buildOwnerSelector(state),
                      const SizedBox(height: LarSpacing.lg),

                      // Card Carousel Deck
                      if (state.cards.isNotEmpty) ...[
                        _buildCardCarousel(state),
                        const SizedBox(height: LarSpacing.lg),

                        // Selected Card Bento Metrics
                        _buildCardMetrics(state),
                        const SizedBox(height: LarSpacing.lg),

                        // Tabs: Fatura Atual vs Próximas Faturas
                        _buildTabs(),
                        const SizedBox(height: LarSpacing.md),

                        if (_tabController.index == 0)
                          _buildCurrentInvoiceTab(state)
                        else
                          _buildFutureInvoicesTab(state),
                      ] else ...[
                        _buildEmptyState(),
                      ],

                      const SizedBox(height: 80),
                    ],
                  ),
                ),
              ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () {
          if (state.cards.isNotEmpty) {
            CardExpenseSheet.show(
              context,
              controller: widget.controller,
              cards: state.cards,
              initialCard: state.selectedCard,
              categories: _categories,
            );
          } else {
            CardFormSheet.show(context, controller: widget.controller);
          }
        },
        backgroundColor: LarColors.champagne,
        foregroundColor: const Color(0xFF0F1714),
        icon: const Icon(Icons.add),
        label: Text(
          state.cards.isNotEmpty ? 'Lançar Compra' : 'Novo Cartão',
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
      ),
    );
  }

  Widget _buildHeader(CardsState state) {
    final monthName = _ptMonths[state.selectedMonth];

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Cartões de Crédito',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 2),
              Text(
                'Faturas, limites e parcelamentos familiares',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Colors.white60,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),

        // Month Selector
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
          decoration: BoxDecoration(
            color: const Color(0xFF101B18),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFF28352E)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                iconSize: 18,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                icon: const Icon(Icons.chevron_left, color: Colors.white70),
                onPressed: _previousMonth,
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Text(
                  '$monthName ${state.selectedYear}',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ),
              IconButton(
                iconSize: 18,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                icon: const Icon(Icons.chevron_right, color: Colors.white70),
                onPressed: _nextMonth,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildOwnerSelector(CardsState state) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          _buildOwnerChip('Lar (Todos)', 'household', state.selectedOwner == 'household'),
          const SizedBox(width: 8),
          _buildOwnerChip('Eu', 'self', state.selectedOwner == 'self'),
          const SizedBox(width: 8),
          _buildOwnerChip('Esposa', 'spouse', state.selectedOwner == 'spouse'),
        ],
      ),
    );
  }

  Widget _buildOwnerChip(String label, String value, bool isSelected) {
    return ChoiceChip(
      label: Text(label),
      selected: isSelected,
      onSelected: (_) => widget.controller.selectOwner(value),
      selectedColor: LarColors.mineral,
      backgroundColor: const Color(0xFF101B18),
      labelStyle: TextStyle(
        fontSize: 12,
        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
        color: isSelected ? Colors.white : Colors.white70,
      ),
      side: BorderSide(
        color: isSelected ? LarColors.mineralOnDark : const Color(0xFF28352E),
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    );
  }

  Widget _buildCardCarousel(CardsState state) {
    return SizedBox(
      height: 180,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: state.cards.length + 1,
        separatorBuilder: (context, index) => const SizedBox(width: 14),
        itemBuilder: (context, index) {
          if (index < state.cards.length) {
            final card = state.cards[index];
            final isSelected = state.selectedCard?.id == card.id;
            return CardItemWidget(
              card: card,
              isSelected: isSelected,
              onTap: () => widget.controller.selectCard(card),
            );
          }
          // Add Card Button
          return GestureDetector(
            onTap: () => CardFormSheet.show(context, controller: widget.controller),
            child: Container(
              width: 140,
              decoration: BoxDecoration(
                color: const Color(0xFF101B18),
                borderRadius: BorderRadius.circular(22),
                border: Border.all(color: const Color(0xFF28352E), style: BorderStyle.solid),
              ),
              child: const Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.add_circle_outline, color: LarColors.mineralOnDark, size: 28),
                  SizedBox(height: 8),
                  Text(
                    'Novo Cartão',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.white70),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildCardMetrics(CardsState state) {
    final card = state.selectedCard;
    final invoice = state.selectedInvoice;
    if (card == null || invoice == null) return const SizedBox.shrink();

    final currencyFmt = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');
    final dateFmt = DateFormat('dd/MM/yyyy');

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF101B18),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: LarColors.mineral.withAlpha(50)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'FATURA ${invoice.month.toString().padLeft(2, '0')}/${invoice.year}',
                      style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 1.1, color: LarColors.champagne),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      currencyFmt.format(invoice.totalAmount),
                      style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.white),
                    ),
                  ],
                ),
              ),
              // Status Badge
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: invoice.isPaid
                      ? LarColors.mineral.withAlpha(40)
                      : (invoice.isOverdue ? LarColors.danger.withAlpha(40) : LarColors.champagne.withAlpha(40)),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: invoice.isPaid
                        ? LarColors.mineralOnDark
                        : (invoice.isOverdue ? LarColors.danger : LarColors.champagne),
                  ),
                ),
                child: Text(
                  invoice.statusDisplay.toUpperCase(),
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: invoice.isPaid
                        ? LarColors.mineralOnDark
                        : (invoice.isOverdue ? LarColors.danger : LarColors.champagne),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Fecha: ${dateFmt.format(invoice.closingDate)}', style: const TextStyle(fontSize: 11, color: Colors.white60)),
              Text('Vence: ${dateFmt.format(invoice.dueDate)}', style: const TextStyle(fontSize: 11, color: Colors.white60)),
            ],
          ),
          const SizedBox(height: 16),

          // Pay / Reopen Button
          if (invoice.isPaid)
            OutlinedButton(
              onPressed: () => widget.controller.reopenInvoice(invoice.id),
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.white70,
                side: const BorderSide(color: Color(0xFF28352E)),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: const Text('Estornar Pagamento da Fatura'),
            )
          else if (invoice.totalAmount > 0)
            SizedBox(
              width: double.infinity,
              height: 44,
              child: FilledButton.icon(
                onPressed: () {
                  PayInvoiceSheet.show(
                    context,
                    controller: widget.controller,
                    invoice: invoice,
                    accounts: _accounts,
                  );
                },
                style: FilledButton.styleFrom(
                  backgroundColor: LarColors.mineral,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                icon: const Icon(Icons.check_circle_outline, size: 18),
                label: const Text('Pagar Fatura', style: TextStyle(fontWeight: FontWeight.bold)),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildTabs() {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF101B18),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF28352E)),
      ),
      child: TabBar(
        controller: _tabController,
        indicator: BoxDecoration(
          color: LarColors.mineral,
          borderRadius: BorderRadius.circular(14),
        ),
        labelColor: Colors.white,
        unselectedLabelColor: Colors.white60,
        labelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
        dividerColor: Colors.transparent,
        tabs: const [
          Tab(text: 'Compras da Fatura'),
          Tab(text: 'Faturas Futuras'),
        ],
      ),
    );
  }

  Widget _buildCurrentInvoiceTab(CardsState state) {
    final invoice = state.selectedInvoice;
    if (invoice == null || invoice.expenses.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(32),
        alignment: Alignment.center,
        child: const Text(
          'Nenhuma compra registrada nesta fatura.',
          style: TextStyle(fontSize: 13, color: Colors.white54),
        ),
      );
    }

    final currencyFmt = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');
    final dateFmt = DateFormat('dd/MM/yyyy');

    return ListView.separated(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: invoice.expenses.length,
      separatorBuilder: (context, index) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        final exp = invoice.expenses[index];
        return Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFF101B18),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFF28352E)),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            exp.description,
                            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.white),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (exp.installmentsCount > 1) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: LarColors.champagne.withAlpha(30),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              '${exp.installmentNumber}/${exp.installmentsCount}x',
                              style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: LarColors.champagne),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${dateFmt.format(exp.date)} • ${exp.categoryName} • ${exp.financialOwnerName}',
                      style: const TextStyle(fontSize: 11, color: Colors.white54),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),

              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    currencyFmt.format(exp.amount),
                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.white),
                  ),
                  const SizedBox(width: 4),
                  IconButton(
                    iconSize: 18,
                    icon: const Icon(Icons.delete_outline, color: Colors.white38),
                    onPressed: () => _confirmDeleteExpense(exp),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildFutureInvoicesTab(CardsState state) {
    if (state.futureInvoices.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(32),
        alignment: Alignment.center,
        child: const Text(
          'Nenhuma parcela projetada para os próximos meses.',
          style: TextStyle(fontSize: 13, color: Colors.white54),
        ),
      );
    }

    final currencyFmt = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');
    final dateFmt = DateFormat('dd/MM/yyyy');

    return ListView.separated(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: state.futureInvoices.length,
      separatorBuilder: (context, index) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        final fInv = state.futureInvoices[index];
        return InkWell(
          onTap: () => widget.controller.selectMonthYear(fInv.month, fInv.year),
          borderRadius: BorderRadius.circular(16),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFF101B18),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFF28352E)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Fatura ${fInv.month.toString().padLeft(2, '0')}/${fInv.year}',
                      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.white),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Vencimento em ${dateFmt.format(fInv.dueDate)}',
                      style: const TextStyle(fontSize: 11, color: Colors.white54),
                    ),
                  ],
                ),
                Text(
                  currencyFmt.format(fInv.totalAmount),
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: LarColors.champagne),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _confirmDeleteExpense(CardExpenseModel expense) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A221E),
        title: const Text('Excluir Compra', style: TextStyle(color: Colors.white)),
        content: Text(
          'Deseja remover "${expense.description}" da fatura?',
          style: const TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancelar'),
          ),
          if (expense.installmentsCount > 1)
            TextButton(
              onPressed: () {
                Navigator.of(ctx).pop();
                widget.controller.deleteExpense(expense.id, deleteAll: true);
              },
              child: const Text('Excluir Todas as Parcelas', style: TextStyle(color: LarColors.danger)),
            ),
          FilledButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              widget.controller.deleteExpense(expense.id);
            },
            style: FilledButton.styleFrom(backgroundColor: LarColors.danger),
            child: const Text('Excluir'),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Container(
      padding: const EdgeInsets.all(40),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: const Color(0xFF101B18),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFF28352E)),
      ),
      child: Column(
        children: [
          const Icon(Icons.credit_card_outlined, size: 48, color: LarColors.mineralOnDark),
          const SizedBox(height: 16),
          const Text('Nenhum cartão cadastrado', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white)),
          const SizedBox(height: 6),
          const Text('Cadastre seus cartões de crédito para acompanhar faturas e parcelamentos.', textAlign: TextAlign.center, style: TextStyle(fontSize: 12, color: Colors.white60)),
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: () => CardFormSheet.show(context, controller: widget.controller),
            style: FilledButton.styleFrom(backgroundColor: LarColors.mineral),
            icon: const Icon(Icons.add),
            label: const Text('Cadastrar Primeiro Cartão'),
          ),
        ],
      ),
    );
  }
}
