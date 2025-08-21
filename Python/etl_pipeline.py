"""
Revenue & Sales Dashboard - ETL Pipeline
Author: Sahil Hansa
Email: sahilhansa007@gmail.com
Description: ETL pipeline for processing multi-source sales data
Location: Jammu, J&K, India
"""

import pandas as pd
import numpy as np
from sqlalchemy import create_engine
from datetime import datetime, timedelta
import logging
from typing import Dict, List
import os
from dotenv import load_dotenv

# Load environment variables
load_dotenv()

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s',
    handlers=[
        logging.FileHandler('logs/etl_pipeline.log'),
        logging.StreamHandler()
    ]
)

class SalesDataETL:
    """
    ETL Pipeline for Sales Data Processing
    
    Author: Sahil Hansa
    Contact: sahilhansa007@gmail.com
    GitHub: https://github.com/SAHIL-HANSA
    """
    
    def __init__(self):
        self.db_connection_string = os.getenv('DATABASE_CONNECTION_STRING')
        self.engine = None
        self.raw_data = {}
        self.processed_data = {}
        
    def connect_to_database(self):
        """Establish database connection"""
        try:
            self.engine = create_engine(self.db_connection_string)
            logging.info("Database connection established successfully")
            return True
        except Exception as e:
            logging.error(f"Failed to connect to database: {str(e)}")
            return False
    
    def extract_sales_data(self) -> Dict[str, pd.DataFrame]:
        """Extract data from multiple sources"""
        logging.info("Starting data extraction process...")
        
        # Extract from SQL Database
        try:
            # Sales transactions data
            sales_query = """
            SELECT 
                transaction_id,
                transaction_date,
                product_id,
                customer_id,
                quantity_sold,
                unit_price,
                total_amount,
                sales_rep_id,
                region_id
            FROM sales_transactions
            WHERE transaction_date >= DATE_SUB(CURDATE(), INTERVAL 2 YEAR)
            """
            
            self.raw_data['sales'] = pd.read_sql(sales_query, self.engine)
            logging.info(f"Extracted {len(self.raw_data['sales'])} sales records")
            
            # Product information
            product_query = """
            SELECT 
                product_id,
                product_name,
                category_id,
                category_name,
                brand,
                cost_price,
                list_price
            FROM products p
            JOIN product_categories pc ON p.category_id = pc.category_id
            """
            
            self.raw_data['products'] = pd.read_sql(product_query, self.engine)
            logging.info(f"Extracted {len(self.raw_data['products'])} product records")
            
            # Customer data
            customer_query = """
            SELECT 
                customer_id,
                customer_name,
                customer_type,
                region_id,
                region_name,
                signup_date
            FROM customers c
            JOIN regions r ON c.region_id = r.region_id
            """
            
            self.raw_data['customers'] = pd.read_sql(customer_query, self.engine)
            logging.info(f"Extracted {len(self.raw_data['customers'])} customer records")
            
        except Exception as e:
            logging.error(f"Error extracting data from database: {str(e)}")
            return {}
        
        # Extract from Excel files
        try:
            # Sales targets from Excel
            self.raw_data['targets'] = pd.read_excel(
                'data/raw/sales_targets_2024.xlsx',
                sheet_name='Monthly_Targets'
            )
            logging.info("Extracted sales targets from Excel file")
            
        except Exception as e:
            logging.error(f"Error extracting Excel data: {str(e)}")
        
        return self.raw_data
    
    def transform_sales_data(self) -> Dict[str, pd.DataFrame]:
        """Transform and clean the extracted data"""
        logging.info("Starting data transformation process...")
        
        try:
            # Transform sales data
            sales_df = self.raw_data['sales'].copy()
            
            # Data cleaning
            sales_df['transaction_date'] = pd.to_datetime(sales_df['transaction_date'])
            sales_df = sales_df.dropna(subset=['transaction_id', 'total_amount'])
            sales_df = sales_df[sales_df['total_amount'] > 0]
            
            # Create derived columns
            sales_df['revenue'] = sales_df['quantity_sold'] * sales_df['unit_price']
            sales_df['profit_margin'] = sales_df['total_amount'] - (sales_df['quantity_sold'] * self.raw_data['products']['cost_price'])
            sales_df['year'] = sales_df['transaction_date'].dt.year
            sales_df['month'] = sales_df['transaction_date'].dt.month
            sales_df['quarter'] = sales_df['transaction_date'].dt.quarter
            sales_df['day_of_week'] = sales_df['transaction_date'].dt.dayofweek
            sales_df['week_of_year'] = sales_df['transaction_date'].dt.isocalendar().week
            
            # Join with product information
            sales_enhanced = sales_df.merge(
                self.raw_data['products'], 
                on='product_id', 
                how='left'
            )
            
            # Join with customer information
            sales_enhanced = sales_enhanced.merge(
                self.raw_data['customers'], 
                on='customer_id', 
                how='left'
            )
            
            self.processed_data['sales_enhanced'] = sales_enhanced
            
            # Create aggregated datasets
            # Monthly revenue summary
            monthly_revenue = sales_enhanced.groupby(['year', 'month', 'region_name']).agg({
                'revenue': 'sum',
                'total_amount': 'sum',
                'quantity_sold': 'sum',
                'transaction_id': 'count'
            }).reset_index()
            monthly_revenue.columns = ['year', 'month', 'region', 'revenue', 'total_sales', 'units_sold', 'transaction_count']
            
            self.processed_data['monthly_revenue'] = monthly_revenue
            
            # Product performance summary
            product_performance = sales_enhanced.groupby(['category_name', 'product_name']).agg({
                'revenue': 'sum',
                'quantity_sold': 'sum',
                'profit_margin': 'sum'
            }).reset_index()
            product_performance = product_performance.sort_values('revenue', ascending=False)
            
            self.processed_data['product_performance'] = product_performance
            
            # Customer segmentation
            customer_metrics = sales_enhanced.groupby('customer_id').agg({
                'revenue': 'sum',
                'transaction_id': 'count',
                'transaction_date': ['min', 'max']
            }).reset_index()
            
            customer_metrics.columns = ['customer_id', 'total_revenue', 'transaction_frequency', 'first_purchase', 'last_purchase']
            customer_metrics['customer_lifetime'] = (customer_metrics['last_purchase'] - customer_metrics['first_purchase']).dt.days
            customer_metrics['avg_order_value'] = customer_metrics['total_revenue'] / customer_metrics['transaction_frequency']
            
            # Customer segmentation logic
            def categorize_customer(row):
                if row['total_revenue'] >= 10000 and row['transaction_frequency'] >= 10:
                    return 'VIP'
                elif row['total_revenue'] >= 5000 or row['transaction_frequency'] >= 5:
                    return 'High Value'
                elif row['total_revenue'] >= 1000:
                    return 'Regular'
                else:
                    return 'Low Value'
            
            customer_metrics['customer_segment'] = customer_metrics.apply(categorize_customer, axis=1)
            self.processed_data['customer_segments'] = customer_metrics
            
            logging.info("Data transformation completed successfully")
            
        except Exception as e:
            logging.error(f"Error during data transformation: {str(e)}")
            return {}
        
        return self.processed_data
    
    def load_processed_data(self) -> bool:
        """Load processed data to destination"""
        logging.info("Starting data loading process...")
        
        try:
            # Save to CSV files for Power BI
            output_dir = 'data/processed/'
            os.makedirs(output_dir, exist_ok=True)
            
            for table_name, dataframe in self.processed_data.items():
                file_path = f"{output_dir}{table_name}.csv"
                dataframe.to_csv(file_path, index=False)
                logging.info(f"Saved {table_name} to {file_path}")
            
            # Load to database tables (optional)
            if self.engine:
                for table_name, dataframe in self.processed_data.items():
                    dataframe.to_sql(
                        name=f"processed_{table_name}", 
                        con=self.engine, 
                        if_exists='replace', 
                        index=False
                    )
                    logging.info(f"Loaded {table_name} to database table processed_{table_name}")
            
            return True
            
        except Exception as e:
            logging.error(f"Error during data loading: {str(e)}")
            return False
    
    def run_etl_pipeline(self) -> bool:
        """Execute complete ETL pipeline"""
        logging.info("Starting ETL pipeline execution...")
        
        # Connect to database
        if not self.connect_to_database():
            return False
        
        # Extract data
        if not self.extract_sales_data():
            logging.error("Data extraction failed")
            return False
        
        # Transform data
        if not self.transform_sales_data():
            logging.error("Data transformation failed")
            return False
        
        # Load data
        if not self.load_processed_data():
            logging.error("Data loading failed")
            return False
        
        logging.info("ETL pipeline completed successfully!")
        return True
    
    def generate_data_quality_report(self) -> Dict:
        """Generate data quality report"""
        report = {}
        
        for table_name, df in self.processed_data.items():
            report[table_name] = {
                'record_count': len(df),
                'null_counts': df.isnull().sum().to_dict(),
                'duplicate_count': df.duplicated().sum(),
                'data_types': df.dtypes.to_dict()
            }
        
        return report

def main():
    """
    Main execution function
    
    Author: Sahil Hansa
    Contact: sahilhansa007@gmail.com
    """
    # Initialize ETL pipeline
    etl = SalesDataETL()
    
    # Run pipeline
    success = etl.run_etl_pipeline()
    
    if success:
        # Generate quality report
        quality_report = etl.generate_data_quality_report()
        
        # Save quality report
        with open('reports/data_quality_report.json', 'w') as f:
            import json
            json.dump(quality_report, f, indent=2, default=str)
        
        print("ETL Pipeline completed successfully!")
        print("Processed data files saved to: data/processed/")
        print("Quality report saved to: reports/data_quality_report.json")
        print("\n--- Project Information ---")
        print("Author: Sahil Hansa")
        print("Email: sahilhansa007@gmail.com")
        print("GitHub: https://github.com/SAHIL-HANSA")
        print("LinkedIn: https://www.linkedin.com/in/sahil-hansa/")
        print("Location: Jammu, J&K, India")
    else:
        print("ETL Pipeline failed. Check logs for details.")

if __name__ == "__main__":
    main()