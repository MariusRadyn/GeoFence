import 'package:flutter/material.dart';
import 'package:geofence/operatorEditPage.dart';
import 'package:geofence/utils.dart';
import 'package:http/http.dart';
import 'package:provider/provider.dart';

class OperatorsPage extends StatefulWidget {
  const OperatorsPage({super.key});

  @override
  State<OperatorsPage> createState() => _OperatorsPageState();
}

class _OperatorsPageState extends State<OperatorsPage> {
  int _selectedIndex = 0;
  OperatorData? selectedOperator;

  @override
  void initState() {
    super.initState();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<OperatorService>().load();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
  }

  @override
  void dispose() {
    super.dispose();
  }

  void _save(OperatorData operator) async {

    OperatorService operatorService = context.read<OperatorService>();
    await operatorService.save(operator);
  }
  void _addNew() async {
    if (!mounted) return;

    OperatorService operatorService = context.read<OperatorService>();
    final docId = await operatorService.addNew();
  }
  void _deleteOperatorDialog(OperatorData operator) async {
    showDialog(
        context: context,
        builder: (context){
          return AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
              side: const BorderSide(
                color: Colors.blue, // Border color
                width: 2, // Border width
              ),
            ),
            backgroundColor: APP_TILE_COLOR,
            shadowColor: Colors.black,
            title: const MyText(
                text: "Delete",
                color: Colors.white
            ),
            content: MyText(
              text: "${operator.name} ${operator.surname}\nAre you sure?",
              color: Colors.grey,
              fontsize: 18,
            ),
            actions: [
              TextButton(
                child: const MyText(
                  text: 'No',
                  fontsize: 20,
                ),
                onPressed: () => Navigator.pop(context),
              ),
              TextButton(
                  child: const MyText(
                    text: 'Yes',
                    color:  Colors.white,
                    fontsize: 20,
                  ),

                  onPressed: () async {
                    _delete(operator);
                    Navigator.pop(context);
                  }
              ),
            ],
          );
        }
    );
  }
  void _delete(OperatorData operator) async {
    if (!mounted) return;

    OperatorService operatorService = context.read<OperatorService>();
    final docId = await operatorService.delete(operator);
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<OperatorService>(
      builder: (_, operatorService, __) {
        return Scaffold(
          appBar: AppBar(
            backgroundColor: APP_BAR_COLOR,
            foregroundColor: Colors.white,
            title: MyAppbarTitle('Operators'),
          ),
          backgroundColor: APP_BACKGROUND_COLOR,
          floatingActionButton: FloatingActionButton(
            backgroundColor: COLOR_ORANGE,
            foregroundColor: Colors.white,
            onPressed: (){
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => OperatorEditPage(
                      operatorData: context.read<OperatorService>().newOperator,
                  ),
                ),
              );
            },
            child: Icon(Icons.add),
          ),
          body: (operatorService.isLoading) ? MyProgressCircle():
            (operatorService.lstOperators.isEmpty) ? MyCenterMsg('No Operators')
            : Column(
            children: [
              SizedBox(height: 10),
              Expanded(
                child: ListView.builder(
                  itemCount: operatorService.lstOperators.length,
                    itemBuilder: (context, index){
                      final operator = operatorService.lstOperators[index];
                      return Column(
                        children: [
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                            child: MyOperatorTile(
                              operator: operator,
                              onTapTile: (){
                                _addNew();
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                      builder: (context) => OperatorEditPage(
                                          operatorData: operator
                                      ),
                                  ),
                                );
                              },
                              onTapDelete: (){
                                _deleteOperatorDialog(operator);
                              },
                            ),
                          )
                        ],
                      );
                    }
                )
              )
            ],
          ),
        );
      },
    );
  }
}

