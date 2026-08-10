import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:renthub_flutter/app/app.dart';
import 'package:renthub_flutter/modules/user/controllers/auth_controller.dart';
import 'package:renthub_flutter/modules/user/repositories/auth_repository.dart';
void main(){testWidgets('shows login screen while signed out',(tester)async{await tester.pumpWidget(ChangeNotifierProvider(create:(_)=>AuthController(MockAuthRepository()),child:const RentHubApp()));expect(find.text('RentHub'),findsOneWidget);expect(find.text('Sign in'),findsOneWidget);});}
