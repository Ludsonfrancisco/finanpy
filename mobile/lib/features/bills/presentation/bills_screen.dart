import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../../design_system/lar_colors.dart';
import '../../../../design_system/lar_spacing.dart';
import '../../accounts/data/accounts_repository.dart';
import '../../accounts/domain/accounts_models.dart';
import '../../home/domain/home_snapshot.dart';
import '../application/bills_controller.dart';
import 'widgets/bill_form_sheet.dart';
import 'widgets/pay_bill_sheet.dart';

final class BillsScreen extends StatefulWidget {
  const BillsScreen({
    required this.controller,
    this.accountsRepository,
    super.key,
  });

  final BillsController controller;
  final AccountsRepository? accountsRepository;

  @override
  State<BillsScreen> createState() => _BillsScreenState();
}

final class _BillsScreenState extends State<BillsScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  List<AccountItem> _accounts = [];

  final List<String> _ptMonths = [
    '',
    'Janeiro',
    'Fevereiro',
    'Março',
    'Abril',
    'Maio',
    'Junho',
    'Julho',
    'Agosto',
    'Setembro',
    'Outubro',
    'Novembro',
    'Dezembro',
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
    _loadAccounts();
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

  Future<void> _loadAccounts() async {
    if (widget.accountsRepository != null) {
      try {
        final stream = widget.accountsRepository!.watchAccounts(
          const OwnerScope.household(),
        );
        final first = await stream.first;
        if (mounted) {
          setState(() {
            _accounts = first.accounts;
          });
        }
      } catch (_) {}
    }
  }

  void _previousMonth() {
    final state = widget.controller.state;
    var m = state.selectedMonth - 1;
    var y = state.selectedYear;
    if (m < 1) {
      m = 12;
      y -= 1;
    }
    widget.controller.setMonth(m, y);
  }

  void _nextMonth() {
    final state = widget.controller.state;
    var m = state.selectedMonth + 1;
    var y = state.selectedYear;
    if (m > 12) {
      m = 1;
      y += 1;
    }
    widget.controller.setMonth(m, y);
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.controller.state;
    final currencyFmt = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');
    final isDesktop = MediaQuery.sizeOf(context).width >= 900;

    return Scaffold(
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: widget.controller.loadData,
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(LarSpacing.xl),
            child: Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1120),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Header with Month Navigation and Add Button
                    _buildHeader(context, state, isDesktop),
                    const SizedBox(height: LarSpacing.lg),

                    // Owner Filter Selector (Lar, Eu, Esposa)
                    _buildOwnerSelector(state),
                    const SizedBox(height: LarSpacing.xl),

                    // 4 Bento Metric Cards (Saldo Livre Real, A Vencer, Pagas, Total)
                    _buildMetricsGrid(state, currencyFmt, isDesktop),
                    const SizedBox(height: LarSpacing.xl),

                    // Tabs
                    Container(
                      decoration: BoxDecoration(
                        color: const Color(0xFF101B18),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: const Color(0xFF28352E)),
                      ),
                      child: TabBar(
                        controller: _tabController,
                        indicatorSize: TabBarIndicatorSize.tab,
                        dividerColor: Colors.transparent,
                        indicator: BoxDecoration(
                          color: LarColors.mineral,
                          borderRadius: BorderRadius.circular(14),
                        ),
                        labelColor: Colors.white,
                        unselectedLabelColor: Colors.white60,
                        tabs: const [
                          Tab(text: 'Vencimentos do Mês'),
                          Tab(text: 'Cadastros Fixos'),
                        ],
                      ),
                    ),
                    const SizedBox(height: LarSpacing.lg),

                    // Tab Content
                    if (state.isLoading)
                      const Center(
                        child: Padding(
                          padding: EdgeInsets.all(40),
                          child: CircularProgressIndicator(
                            color: LarColors.mineral,
                          ),
                        ),
                      )
                    else if (state.activeTab == 0)
                      _buildInstancesList(state, currencyFmt)
                    else
                      _buildRecurringBillsList(state, currencyFmt),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: LarColors.mineral,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add),
        label: const Text(
          'Nova Conta Fixa',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        onPressed: () {
          BillFormSheet.show(
            context,
            onSave: widget.controller.createRecurringBill,
          );
        },
      ),
    );
  }

  Widget _buildHeader(BuildContext context, BillsState state, bool isDesktop) {
    final monthName = _ptMonths[state.selectedMonth];

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Contas Fixas & Vencimentos',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 2),
              Text(
                'Previsibilidade financeira da casa e gestão de compromissos fixos',
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: Colors.white60),
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
              Text(
                '$monthName ${state.selectedYear}',
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
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

  Widget _buildOwnerSelector(BillsState state) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          _ownerChip(
            'household',
            'Lar (Todos)',
            state.ownerFilter == 'household',
          ),
          const SizedBox(width: LarSpacing.xs),
          _ownerChip('self', 'Eu', state.ownerFilter == 'self'),
          const SizedBox(width: LarSpacing.xs),
          _ownerChip('spouse', 'Esposa', state.ownerFilter == 'spouse'),
          const SizedBox(width: LarSpacing.xs),
          _ownerChip('shared', 'Conjunto', state.ownerFilter == 'shared'),
        ],
      ),
    );
  }

  Widget _ownerChip(String key, String label, bool selected) {
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      selectedColor: LarColors.mineral,
      backgroundColor: const Color(0xFF101B18),
      labelStyle: TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.bold,
        color: selected ? Colors.white : Colors.white60,
      ),
      side: BorderSide(
        color: selected ? LarColors.mineral : const Color(0xFF28352E),
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      onSelected: (_) => widget.controller.setOwnerFilter(key),
    );
  }

  Widget _buildMetricsGrid(
    BillsState state,
    NumberFormat currencyFmt,
    bool isDesktop,
  ) {
    final m = state.metrics;

    final cards = [
      _buildMetricCard(
        title: 'Saldo Livre Real',
        value: currencyFmt.format(m.freeCashBalance),
        subtitle: 'Disponível após faturas a vencer',
        color: m.freeCashBalance >= 0
            ? LarColors.mineralOnDark
            : LarColors.danger,
        icon: Icons.shield_outlined,
        isHighlight: true,
      ),
      _buildMetricCard(
        title: 'A Vencer no Mês',
        value: currencyFmt.format(m.pendingExpensesTotal),
        subtitle: m.overdueCount > 0 ? '${m.overdueCount} em atraso' : 'Em dia',
        color: m.overdueCount > 0 ? LarColors.danger : Colors.white,
        icon: Icons.schedule,
      ),
      _buildMetricCard(
        title: 'Já Pagas',
        value: currencyFmt.format(m.paidExpensesTotal),
        subtitle: 'Baixadas no extrato',
        color: LarColors.mineralOnDark,
        icon: Icons.check_circle_outline,
      ),
      _buildMetricCard(
        title: 'Total Comprometido',
        value: currencyFmt.format(m.totalCommitted),
        subtitle: 'Orçamento fixo',
        color: Colors.white,
        icon: Icons.receipt_long_outlined,
      ),
    ];

    if (isDesktop) {
      return Row(
        children: cards
            .map(
              (c) => Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  child: c,
                ),
              ),
            )
            .toList(),
      );
    }

    return Column(
      children: [
        cards[0],
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(child: cards[1]),
            const SizedBox(width: 10),
            Expanded(child: cards[2]),
          ],
        ),
      ],
    );
  }

  Widget _buildMetricCard({
    required String title,
    required String value,
    required String subtitle,
    required Color color,
    required IconData icon,
    bool isHighlight = false,
  }) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: isHighlight ? const Color(0xFF14241F) : const Color(0xFF101B18),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: isHighlight ? LarColors.mineral : const Color(0xFF28352E),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  title.toUpperCase(),
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.1,
                    color: isHighlight
                        ? LarColors.mineralOnDark
                        : Colors.white60,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 4),
              Icon(
                icon,
                size: 18,
                color: isHighlight ? LarColors.mineralOnDark : Colors.white54,
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            style: const TextStyle(fontSize: 11, color: Colors.white54),
          ),
        ],
      ),
    );
  }

  Widget _buildInstancesList(BillsState state, NumberFormat currencyFmt) {
    if (state.instances.isEmpty) {
      return _buildEmptyState('Nenhuma fatura de conta fixa para este mês.');
    }

    final now = DateTime.now();

    return ListView.separated(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: state.instances.length,
      separatorBuilder: (context, index) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        final item = state.instances[index];
        final isOverdue = item.isOverdue(now);

        return Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFF101B18),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: item.isPaid
                  ? LarColors.mineral
                  : isOverdue
                  ? LarColors.danger
                  : const Color(0xFF28352E),
            ),
          ),
          child: Row(
            children: [
              // Due Day Badge
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: item.isPaid
                      ? const Color(0xFF1B3D37)
                      : isOverdue
                      ? const Color(0xFF4A1E1C)
                      : const Color(0xFF182622),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      'DIA',
                      style: TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.bold,
                        color: item.isPaid
                            ? LarColors.mineralOnDark
                            : isOverdue
                            ? LarColors.danger
                            : Colors.white60,
                      ),
                    ),
                    Text(
                      '${item.dueDay}',
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 14),

              // Info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.name,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Row(
                      children: [
                        Text(
                          item.categoryName,
                          style: const TextStyle(
                            fontSize: 11,
                            color: Colors.white60,
                          ),
                        ),
                        const Text(
                          ' • ',
                          style: TextStyle(fontSize: 11, color: Colors.white38),
                        ),
                        Text(
                          item.financialOwnerName,
                          style: const TextStyle(
                            fontSize: 11,
                            color: Colors.white60,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              // Amount & Action
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    currencyFmt.format(item.amount),
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                      color: item.type == 'income'
                          ? LarColors.mineralOnDark
                          : Colors.white,
                    ),
                  ),
                  const SizedBox(height: 6),
                  if (item.isPaid)
                    OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        side: const BorderSide(color: Color(0xFF28352E)),
                      ),
                      onPressed: () async {
                        final confirm = await showDialog<bool>(
                          context: context,
                          builder: (c) => AlertDialog(
                            title: const Text('Desfazer Pagamento?'),
                            content: Text(
                              'Deseja estornar o pagamento de "${item.name}"?',
                            ),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(c, false),
                                child: const Text('Cancelar'),
                              ),
                              FilledButton(
                                style: FilledButton.styleFrom(
                                  backgroundColor: LarColors.danger,
                                ),
                                onPressed: () => Navigator.pop(c, true),
                                child: const Text('Sim, Desfazer'),
                              ),
                            ],
                          ),
                        );
                        if (confirm == true) {
                          await widget.controller.reopenBill(item.id);
                        }
                      },
                      child: const Text(
                        'Desfazer',
                        style: TextStyle(fontSize: 11, color: Colors.white70),
                      ),
                    )
                  else
                    FilledButton.icon(
                      style: FilledButton.styleFrom(
                        backgroundColor: LarColors.mineral,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      icon: const Icon(Icons.check, size: 14),
                      label: const Text(
                        'Pagar',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      onPressed: () {
                        PayBillSheet.show(
                          context,
                          instance: item,
                          accounts: _accounts,
                          onPay:
                              ({
                                required accountId,
                                required paidAmount,
                                required paidDate,
                              }) => widget.controller.payBill(
                                instanceId: item.id,
                                accountId: accountId,
                                paidAmount: paidAmount,
                                paidDate: paidDate,
                              ),
                        );
                      },
                    ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildRecurringBillsList(BillsState state, NumberFormat currencyFmt) {
    if (state.recurringBills.isEmpty) {
      return _buildEmptyState('Nenhuma regra de conta fixa cadastrada.');
    }

    return ListView.separated(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: state.recurringBills.length,
      separatorBuilder: (context, index) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        final bill = state.recurringBills[index];

        return Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFF101B18),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFF28352E)),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          bill.name,
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(width: 8),
                        if (!bill.isActive)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.white10,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: const Text(
                              'Inativa',
                              style: TextStyle(
                                fontSize: 9,
                                color: Colors.white60,
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Vence todo dia ${bill.dueDay} • ${bill.categoryName} • ${bill.financialOwnerName}',
                      style: const TextStyle(
                        fontSize: 11,
                        color: Colors.white60,
                      ),
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    currencyFmt.format(bill.amount),
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        iconSize: 16,
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(
                          minWidth: 28,
                          minHeight: 28,
                        ),
                        icon: const Icon(
                          Icons.edit_outlined,
                          color: Colors.white70,
                        ),
                        onPressed: () {
                          BillFormSheet.show(
                            context,
                            initialBill: bill,
                            onSave:
                                ({
                                  required name,
                                  required amount,
                                  required dueDay,
                                  required type,
                                  financialOwnerType,
                                  isActive = true,
                                  notes = '',
                                }) => widget.controller.updateRecurringBill(
                                  bill.id,
                                  name: name,
                                  amount: amount,
                                  dueDay: dueDay,
                                  type: type,
                                  financialOwnerType: financialOwnerType,
                                  isActive: isActive,
                                  notes: notes,
                                ),
                          );
                        },
                      ),
                      IconButton(
                        iconSize: 16,
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(
                          minWidth: 28,
                          minHeight: 28,
                        ),
                        icon: const Icon(
                          Icons.delete_outline,
                          color: LarColors.danger,
                        ),
                        onPressed: () async {
                          final confirm = await showDialog<bool>(
                            context: context,
                            builder: (c) => AlertDialog(
                              title: const Text('Excluir Conta Fixa?'),
                              content: Text(
                                'Deseja excluir a regra "${bill.name}"?',
                              ),
                              actions: [
                                TextButton(
                                  onPressed: () => Navigator.pop(c, false),
                                  child: const Text('Cancelar'),
                                ),
                                FilledButton(
                                  style: FilledButton.styleFrom(
                                    backgroundColor: LarColors.danger,
                                  ),
                                  onPressed: () => Navigator.pop(c, true),
                                  child: const Text('Sim, Excluir'),
                                ),
                              ],
                            ),
                          );
                          if (confirm == true) {
                            await widget.controller.deleteRecurringBill(
                              bill.id,
                            );
                          }
                        },
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildEmptyState(String message) {
    return Container(
      padding: const EdgeInsets.all(40),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: const Color(0xFF101B18),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF28352E)),
      ),
      child: Column(
        children: [
          const Icon(
            Icons.calendar_month_outlined,
            size: 40,
            color: Colors.white38,
          ),
          const SizedBox(height: 12),
          Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 13, color: Colors.white70),
          ),
        ],
      ),
    );
  }
}
