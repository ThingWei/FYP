import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../controllers/listing_controller.dart';
class ListingScreen extends StatelessWidget { const ListingScreen({super.key}); @override Widget build(BuildContext context){final c=context.watch<ListingController>();if(c.loading&&c.listings.isEmpty)return const Center(child:CircularProgressIndicator());return RefreshIndicator(onRefresh:c.load,child:ListView(padding:const EdgeInsets.all(16),children:[Text('Discover rentals',style:Theme.of(context).textTheme.headlineMedium),const SizedBox(height:12),...c.listings.map((x)=>Card(child:ListTile(title:Text(x.title),subtitle:Text('${x.category} • ${x.condition}'),trailing:Text('RM ${x.dailyPrice.toStringAsFixed(0)}/day'))))]));} }

